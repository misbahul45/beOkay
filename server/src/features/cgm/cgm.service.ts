import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { AppError, notFound, unprocessable } from "../../shared/errors/app-error.ts";
import { rateWindow } from "../../shared/http/rate-window.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { consentService } from "../consent/consent.service.ts";
import { zonedToUtc } from "../medication/medication.model.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { CGM_BANDS, CGM_SUMMARY_VERSION, SUFFICIENT_COVERAGE, summarizeCgm } from "./cgm.model.ts";
import { CGM_PARSER_VERSION, MMOL_TO_MGDL, parseLibreView, type DateOrder } from "./cgm.parser.ts";

const imports = rateWindow(60 * 60_000, 10);
const DAY = 86_400_000;
const SOURCE = "LIBREVIEW";

type ImportRow = NonNullable<Awaited<ReturnType<typeof prisma.cgmImport.findFirst>>>;
const importView = (r: ImportRow) => ({
  id: r.id,
  source: r.source,
  fileName: r.fileName,
  device: r.device,
  unit: r.unit,
  rowsTotal: r.rowsTotal,
  rowsAccepted: r.rowsAccepted,
  rowsDuplicate: r.rowsDuplicate,
  rowsSkipped: r.rowsSkipped,
  periodStart: r.periodStart?.toISOString() ?? null,
  periodEnd: r.periodEnd?.toISOString() ?? null,
  parserVersion: r.parserVersion,
  createdAt: r.createdAt.toISOString(),
});

export const cgmService = {
  async importCsv(userId: string, csv: string, opts: { fileName?: string | null; dateOrder?: DateOrder | "auto" }, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    if (imports.full(userId, now.getTime())) throw new AppError(429, "CGM_RATE_LIMITED", "Terlalu sering mengimpor. Coba lagi dalam satu jam.");
    imports.record(userId, now.getTime());
    const parsed = parseLibreView(csv, { dateOrder: opts.dateOrder ?? "auto" });
    if (!parsed.ok) throw unprocessable(parsed.code, parsed.message);
    const { timezone } = await preferencesService.get(userId);
    const limit = now.getTime() + 5 * 60_000;
    const seen = new Set<string>();
    const rows: { userId: string; measuredAt: Date; valueMgDl: number; kind: string; source: string }[] = [];
    for (const r of parsed.readings) {
      const at = zonedToUtc(r.localDate, r.localTime, timezone);
      const key = `${r.kind}:${at.getTime()}`;
      if (at.getTime() > limit || seen.has(key)) continue;
      seen.add(key);
      rows.push({ userId, measuredAt: at, valueMgDl: r.valueMgDl, kind: r.kind, source: SOURCE });
    }
    const times = rows.map((r) => r.measuredAt.getTime());
    const fileName = opts.fileName?.trim().slice(0, 200) || null;
    const saved = await prisma.$transaction(
      async (tx) => {
        const imp = await tx.cgmImport.create({ data: { userId, source: SOURCE, fileName, device: parsed.device, unit: parsed.unit, rowsTotal: 0, rowsAccepted: 0, rowsDuplicate: 0, rowsSkipped: 0, parserVersion: CGM_PARSER_VERSION, createdAt: now } });
        let accepted = 0;
        for (let i = 0; i < rows.length; i += 2000) {
          const batch = rows.slice(i, i + 2000).map((r) => ({ ...r, importId: imp.id }));
          accepted += (await tx.cgmReading.createMany({ data: batch, skipDuplicates: true })).count;
        }
        const done = await tx.cgmImport.update({
          where: { id: imp.id },
          data: {
            rowsTotal: parsed.total,
            rowsAccepted: accepted,
            rowsDuplicate: rows.length - accepted,
            rowsSkipped: parsed.total - rows.length,
            periodStart: times.length ? new Date(Math.min(...times)) : null,
            periodEnd: times.length ? new Date(Math.max(...times)) : null,
          },
        });
        await recordAudit(tx, { userId, eventType: "cgm_imported", metadata: { importId: imp.id, accepted, duplicate: rows.length - accepted, skipped: parsed.total - rows.length } });
        return done;
      },
      { timeout: 30_000 },
    );
    return { ...importView(saved), dateOrder: parsed.dateOrder };
  },

  async list(userId: string) {
    await consentService.requireConsent(userId, "health_data_processing");
    const rows = await prisma.cgmImport.findMany({ where: { userId }, orderBy: { createdAt: "desc" }, take: 20 });
    return { items: rows.map(importView) };
  },

  async remove(userId: string, id: string) {
    const row = await prisma.cgmImport.findFirst({ where: { id, userId } });
    if (!row) throw notFound("CGM_IMPORT_NOT_FOUND", "Impor tidak ditemukan.");
    await prisma.$transaction(async (tx) => {
      await tx.cgmImport.delete({ where: { id } });
      await recordAudit(tx, { userId, eventType: "cgm_import_deleted", metadata: { importId: id, readings: row.rowsAccepted } });
    });
    return { deleted: true, id };
  },

  async summary(userId: string, days: 14 | 30 | 90, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    const { timezone, glucoseUnit } = await preferencesService.get(userId);
    const today = localRecordTime(now, timezone).localDate;
    const startLocal = new Date(Date.parse(today + "T00:00:00Z") - (days - 1) * DAY).toISOString().slice(0, 10);
    const from = zonedToUtc(startLocal, "00:00", timezone);
    const rows = await prisma.cgmReading.findMany({ where: { userId, measuredAt: { gte: from, lte: now } }, select: { measuredAt: true, valueMgDl: true, kind: true }, orderBy: { measuredAt: "asc" } });
    const s = summarizeCgm(rows.map((r) => ({ measuredAt: r.measuredAt, valueMgDl: r.valueMgDl.toNumber(), kind: r.kind })), days);
    const limitations: string[] = [];
    if (s.readings === 0) limitations.push("Belum ada data sensor pada periode ini.");
    else if (s.kindUsed === "SCAN") limitations.push("Hanya bacaan pindaian yang tersedia; persentase waktu tidak mewakili seluruh hari.");
    else if (!s.sufficient) limitations.push(`Data terekam kurang dari ${SUFFICIENT_COVERAGE}% periode; ringkasan bisa tidak mewakili.`);
    return {
      version: CGM_SUMMARY_VERSION,
      period: { start: startLocal, end: today },
      days,
      timezone,
      glucoseUnit,
      thresholdsMgDl: CGM_BANDS,
      ...s,
      meanMmolL: s.meanMgDl === null ? null : Math.round((s.meanMgDl / MMOL_TO_MGDL) * 10) / 10,
      limitations,
      notice: "Ringkasan deskriptif dari sensor. Bukan saran dosis atau pengobatan; bicarakan hasilnya dengan dokter.",
    };
  },
};
