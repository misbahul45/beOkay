import { createHash } from "node:crypto";
import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { conflict, notFound, unprocessable } from "../../shared/errors/app-error.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { consentService } from "../consent/consent.service.ts";
import { emitRecordEvent } from "../events/record-events.ts";
import { notificationService } from "../notifications/notification.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { CLINICAL_SUMMARY_VERSION, LAB_RULES, LAB_TESTS, VITAL_KINDS, VITAL_RULES, change, hba1cStatus, labProblem, vitalProblem, type LabTest, type VitalKind } from "./clinical.model.ts";
import type { LabInput, LabPatch, VitalInput, VitalPatch } from "./clinical.schema.ts";

type Vital = NonNullable<Awaited<ReturnType<typeof prisma.vitalMeasurement.findFirst>>>;
type Lab = NonNullable<Awaited<ReturnType<typeof prisma.labResult.findFirst>>>;

const sha = (v: unknown) => createHash("sha256").update(JSON.stringify(v)).digest("hex");
const isUnique = (e: unknown) => e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002";
const num = (d: Prisma.Decimal | null) => (d === null ? null : d.toNumber());
const requireHealth = (userId: string) => consentService.requireConsent(userId, "health_data_processing");

function vitalView(v: Vital, timezone: string) {
  return {
    id: v.id,
    kind: v.kind,
    label: VITAL_RULES[v.kind as VitalKind]?.label ?? v.kind,
    value: v.value.toNumber(),
    value2: num(v.value2),
    unit: v.unit,
    display: v.kind === "blood_pressure" ? `${v.value.toNumber()}/${num(v.value2)} ${v.unit}` : `${v.value.toNumber()} ${v.unit}`,
    measuredAt: v.measuredAt.toISOString(),
    ...localRecordTime(v.measuredAt, timezone),
    source: v.source,
    notes: v.notes,
    version: v.version,
    archivedAt: v.archivedAt?.toISOString() ?? null,
    createdAt: v.createdAt.toISOString(),
    updatedAt: v.updatedAt.toISOString(),
  };
}

function labView(l: Lab) {
  return {
    id: l.id,
    test: l.test,
    label: LAB_RULES[l.test as LabTest]?.label ?? l.test,
    value: l.value.toNumber(),
    unit: l.unit,
    display: `${l.value.toNumber()} ${l.unit}`,
    sampledAt: l.sampledAt.toISOString().slice(0, 10),
    labName: l.labName,
    source: l.source,
    notes: l.notes,
    version: l.version,
    archivedAt: l.archivedAt?.toISOString() ?? null,
    createdAt: l.createdAt.toISOString(),
    updatedAt: l.updatedAt.toISOString(),
  };
}

function checkVital(kind: VitalKind, unit: string, value: number, value2: number | null) {
  const problem = vitalProblem(kind, unit, value, value2);
  if (problem) throw unprocessable(problem, "Nilai atau satuan di luar batas yang bisa dicatat.", { kind, unit });
}

function checkLab(test: LabTest, unit: string, value: number) {
  const problem = labProblem(test, unit, value);
  if (problem) throw unprocessable(problem, "Nilai atau satuan di luar batas yang bisa dicatat.", { test, unit, allowedUnits: Object.keys(LAB_RULES[test].units) });
}

const findVital = (userId: string, id: string, db: Prisma.TransactionClient | typeof prisma = prisma) => db.vitalMeasurement.findFirst({ where: { id, userId } });
const findLab = (userId: string, id: string, db: Prisma.TransactionClient | typeof prisma = prisma) => db.labResult.findFirst({ where: { id, userId } });

export const clinicalService = {
  async createVital(userId: string, input: VitalInput) {
    await requireHealth(userId);
    checkVital(input.kind, input.unit, input.value, input.value2);
    const { timezone } = await preferencesService.get(userId);
    const hash = sha(input);
    try {
      const row = await prisma.$transaction(async (tx) => {
        const old = await findVital(userId, input.id, tx);
        if (old) {
          if (old.createHash !== hash) throw conflict("IDEMPOTENCY_CONFLICT", "ID pengukuran sudah digunakan dengan isi berbeda.");
          return old;
        }
        const saved = await tx.vitalMeasurement.create({ data: { ...input, userId, measuredAt: new Date(input.measuredAt), createHash: hash } });
        await recordAudit(tx, { userId, eventType: "vital_recorded", metadata: { recordId: saved.id, kind: saved.kind } });
        await emitRecordEvent(tx, { userId, kind: "vital", action: "created", recordId: saved.id, revision: saved.version, occurredAt: saved.measuredAt, localDates: [localRecordTime(saved.measuredAt, timezone).localDate], timezone, source: saved.source, quality: "user_reported" });
        return saved;
      });
      return vitalView(row, timezone);
    } catch (e) {
      if (isUnique(e)) {
        const old = await findVital(userId, input.id);
        if (old?.createHash === hash) return vitalView(old, timezone);
        throw conflict("IDEMPOTENCY_CONFLICT", "ID pengukuran sudah digunakan.");
      }
      throw e;
    }
  },

  async getVital(userId: string, id: string) {
    await requireHealth(userId);
    const [row, { timezone }] = await Promise.all([findVital(userId, id), preferencesService.get(userId)]);
    if (!row) throw notFound("VITAL_NOT_FOUND", "Pengukuran tidak ditemukan.");
    return vitalView(row, timezone);
  },

  async updateVital(userId: string, id: string, input: VitalPatch) {
    await requireHealth(userId);
    const { timezone } = await preferencesService.get(userId);
    const row = await prisma.$transaction(async (tx) => {
      const old = await findVital(userId, id, tx);
      if (!old) throw notFound("VITAL_NOT_FOUND", "Pengukuran tidak ditemukan.");
      if (old.version !== input.expectedVersion) throw conflict("VERSION_CONFLICT", "Pengukuran berubah. Muat ulang sebelum mengoreksi.");
      const { expectedVersion, reason, archived, measuredAt, ...fields } = input;
      const value = fields.value ?? old.value.toNumber();
      const value2 = fields.value2 === undefined ? num(old.value2) : fields.value2;
      const unit = fields.unit ?? old.unit;
      checkVital(old.kind as VitalKind, unit, value, value2);
      const changed = await tx.vitalMeasurement.updateMany({
        where: { id, userId, version: expectedVersion },
        data: { ...fields, measuredAt: measuredAt ? new Date(measuredAt) : undefined, archivedAt: archived === undefined ? undefined : archived ? new Date() : null, version: { increment: 1 } },
      });
      if (changed.count !== 1) throw conflict("VERSION_CONFLICT", "Pengukuran berubah. Muat ulang sebelum mengoreksi.");
      await tx.recordRevision.create({ data: { userId, vitalId: id, version: old.version, reason, snapshot: JSON.parse(JSON.stringify(vitalView(old, timezone))) } });
      await recordAudit(tx, { userId, eventType: archived ? "vital_archived" : "vital_corrected", metadata: { recordId: id, version: old.version + 1 } });
      const after = (await findVital(userId, id, tx))!;
      await emitRecordEvent(tx, { userId, kind: "vital", action: archived ? "archived" : "corrected", recordId: id, revision: after.version, occurredAt: after.measuredAt, localDates: [localRecordTime(after.measuredAt, timezone).localDate], timezone, source: after.source, quality: "user_reported" });
      return after;
    });
    return vitalView(row, timezone);
  },

  async listVitals(userId: string, q: { kind?: VitalKind; cursor?: string; limit: number; archived: string }) {
    await requireHealth(userId);
    const { timezone } = await preferencesService.get(userId);
    const anchor = q.cursor ? await findVital(userId, q.cursor) : null;
    if (q.cursor && !anchor) throw notFound("CURSOR_NOT_FOUND", "Cursor tidak ditemukan.");
    const rows = await prisma.vitalMeasurement.findMany({
      where: { userId, archivedAt: q.archived === "true" ? { not: null } : null, ...(q.kind ? { kind: q.kind } : {}), ...(anchor ? { OR: [{ measuredAt: { lt: anchor.measuredAt } }, { measuredAt: anchor.measuredAt, id: { lt: anchor.id } }] } : {}) },
      orderBy: [{ measuredAt: "desc" }, { id: "desc" }],
      take: q.limit + 1,
    });
    const page = rows.slice(0, q.limit);
    return { items: page.map((r) => vitalView(r, timezone)), nextCursor: rows.length > q.limit ? page.at(-1)!.id : null, timezone };
  },

  async vitalRevisions(userId: string, id: string) {
    await this.getVital(userId, id);
    return { items: await prisma.recordRevision.findMany({ where: { userId, vitalId: id }, orderBy: { version: "desc" } }) };
  },

  async createLab(userId: string, input: LabInput) {
    await requireHealth(userId);
    checkLab(input.test, input.unit, input.value);
    const hash = sha(input);
    try {
      const row = await prisma.$transaction(async (tx) => {
        const old = await findLab(userId, input.id, tx);
        if (old) {
          if (old.createHash !== hash) throw conflict("IDEMPOTENCY_CONFLICT", "ID hasil lab sudah digunakan dengan isi berbeda.");
          return old;
        }
        const saved = await tx.labResult.create({ data: { ...input, userId, sampledAt: new Date(input.sampledAt + "T00:00:00Z"), createHash: hash } });
        await recordAudit(tx, { userId, eventType: "lab_recorded", metadata: { recordId: saved.id, test: saved.test } });
        return saved;
      });
      return labView(row);
    } catch (e) {
      if (isUnique(e)) {
        const old = await findLab(userId, input.id);
        if (old?.createHash === hash) return labView(old);
        throw conflict("IDEMPOTENCY_CONFLICT", "ID hasil lab sudah digunakan.");
      }
      throw e;
    }
  },

  async getLab(userId: string, id: string) {
    await requireHealth(userId);
    const row = await findLab(userId, id);
    if (!row) throw notFound("LAB_NOT_FOUND", "Hasil lab tidak ditemukan.");
    return labView(row);
  },

  async updateLab(userId: string, id: string, input: LabPatch) {
    await requireHealth(userId);
    const row = await prisma.$transaction(async (tx) => {
      const old = await findLab(userId, id, tx);
      if (!old) throw notFound("LAB_NOT_FOUND", "Hasil lab tidak ditemukan.");
      if (old.version !== input.expectedVersion) throw conflict("VERSION_CONFLICT", "Hasil lab berubah. Muat ulang sebelum mengoreksi.");
      const { expectedVersion, reason, archived, sampledAt, ...fields } = input;
      checkLab(old.test as LabTest, fields.unit ?? old.unit, fields.value ?? old.value.toNumber());
      const changed = await tx.labResult.updateMany({
        where: { id, userId, version: expectedVersion },
        data: { ...fields, sampledAt: sampledAt ? new Date(sampledAt + "T00:00:00Z") : undefined, archivedAt: archived === undefined ? undefined : archived ? new Date() : null, version: { increment: 1 } },
      });
      if (changed.count !== 1) throw conflict("VERSION_CONFLICT", "Hasil lab berubah. Muat ulang sebelum mengoreksi.");
      await tx.recordRevision.create({ data: { userId, labId: id, version: old.version, reason, snapshot: JSON.parse(JSON.stringify(labView(old))) } });
      await recordAudit(tx, { userId, eventType: archived ? "lab_archived" : "lab_corrected", metadata: { recordId: id, version: old.version + 1 } });
      return (await findLab(userId, id, tx))!;
    });
    return labView(row);
  },

  async listLabs(userId: string, q: { test?: LabTest; cursor?: string; limit: number; archived: string }) {
    await requireHealth(userId);
    const anchor = q.cursor ? await findLab(userId, q.cursor) : null;
    if (q.cursor && !anchor) throw notFound("CURSOR_NOT_FOUND", "Cursor tidak ditemukan.");
    const rows = await prisma.labResult.findMany({
      where: { userId, archivedAt: q.archived === "true" ? { not: null } : null, ...(q.test ? { test: q.test } : {}), ...(anchor ? { OR: [{ sampledAt: { lt: anchor.sampledAt } }, { sampledAt: anchor.sampledAt, id: { lt: anchor.id } }] } : {}) },
      orderBy: [{ sampledAt: "desc" }, { id: "desc" }],
      take: q.limit + 1,
    });
    const page = rows.slice(0, q.limit);
    return { items: page.map(labView), nextCursor: rows.length > q.limit ? page.at(-1)!.id : null };
  },

  async labRevisions(userId: string, id: string) {
    await this.getLab(userId, id);
    return { items: await prisma.recordRevision.findMany({ where: { userId, labId: id }, orderBy: { version: "desc" } }) };
  },

  async summary(userId: string, now = new Date()) {
    await requireHealth(userId);
    await consentService.requireConsent(userId, "descriptive_summaries");
    const { timezone } = await preferencesService.get(userId);
    const today = localRecordTime(now, timezone).localDate;
    const [vitals, labs] = await Promise.all([
      Promise.all(VITAL_KINDS.map((kind) => prisma.vitalMeasurement.findMany({ where: { userId, kind, archivedAt: null }, orderBy: [{ measuredAt: "desc" }, { id: "desc" }], take: 2 }))),
      Promise.all(LAB_TESTS.map((test) => prisma.labResult.findMany({ where: { userId, test, archivedAt: null }, orderBy: [{ sampledAt: "desc" }, { id: "desc" }], take: 2 }))),
    ]);
    const vitalItems = VITAL_KINDS.map((kind, i) => {
      const [latest, previous] = vitals[i]!;
      return {
        kind,
        label: VITAL_RULES[kind].label,
        latest: latest ? vitalView(latest, timezone) : null,
        previous: previous ? vitalView(previous, timezone) : null,
        change: latest && previous && latest.unit === previous.unit ? change(latest.value.toNumber(), previous.value.toNumber()) : null,
        change2: latest && previous && kind === "blood_pressure" ? change(num(latest.value2), num(previous.value2)) : null,
      };
    });
    const labItems = LAB_TESTS.map((test, i) => {
      const [latest, previous] = labs[i]!;
      return {
        test,
        label: LAB_RULES[test].label,
        latest: latest ? labView(latest) : null,
        previous: previous ? labView(previous) : null,
        change: latest && previous && latest.unit === previous.unit ? change(latest.value.toNumber(), previous.value.toNumber()) : null,
      };
    });
    const lastHba1c = labs[0]![0];
    return {
      date: today,
      timezone,
      vitals: vitalItems,
      labs: labItems,
      hba1c: hba1cStatus(lastHba1c ? lastHba1c.sampledAt.toISOString().slice(0, 10) : null, today),
      notice: "Angka ditampilkan apa adanya, tanpa penilaian klinis. Diskusikan hasilmu dengan tenaga kesehatan.",
      computationVersion: CLINICAL_SUMMARY_VERSION,
      computedAt: now.toISOString(),
    };
  },

  async remindDueLabs(now = new Date()) {
    const latest = await prisma.labResult.findMany({ where: { test: "hba1c", archivedAt: null }, orderBy: [{ userId: "asc" }, { sampledAt: "desc" }], distinct: ["userId"], select: { id: true, userId: true, sampledAt: true }, take: 2000 });
    let sent = 0;
    for (const row of latest) {
      const { timezone } = await preferencesService.get(row.userId);
      const today = localRecordTime(now, timezone).localDate;
      const status = hba1cStatus(row.sampledAt.toISOString().slice(0, 10), today);
      if (status.status !== "DUE") continue;
      try {
        await consentService.requireConsent(row.userId, "health_data_processing");
      } catch {
        continue;
      }
      const made = await notificationService.notify(row.userId, { kind: "LAB_REMINDER", title: "Sudah 3 bulan sejak HbA1c terakhir", body: "Bila kamu sudah periksa, catat hasilnya. Jadwal periksa tetap mengikuti saran tenaga kesehatanmu.", action: "OPEN_CLINICAL", refId: row.id, dedupeKey: `lab:hba1c:${row.id}` });
      if (made) sent++;
    }
    return { candidates: latest.length, sent };
  },
};
