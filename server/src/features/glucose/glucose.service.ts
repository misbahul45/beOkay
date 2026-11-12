import { createHash } from "node:crypto";
import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import {
  conflict,
  notFound,
  unprocessable,
} from "../../shared/errors/app-error.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { consentService } from "../consent/consent.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import type { GlucoseUnit } from "../preferences/glucose-units.ts";
import { canonicalGlucose, displayGlucose } from "./glucose.model.ts";
import { glucoseAlert } from "./glucose.alerts.ts";
import { glucoseRepository } from "./glucose.repository.ts";
import type { GlucoseInput, GlucosePatch } from "./glucose.schema.ts";

type Row = NonNullable<Awaited<ReturnType<typeof glucoseRepository.find>>>;
type Settings = Awaited<ReturnType<typeof preferencesService.get>>;
function view(row: Row, settings: Settings) {
  const unit = settings.glucoseUnit as GlucoseUnit;
  return {
    id: row.id,
    originalValue: row.originalValue.toNumber(),
    originalUnit: row.originalUnit,
    valueMgDl: row.valueMgDl.toNumber(),
    displayValue:
      unit === row.originalUnit
        ? row.originalValue.toNumber()
        : displayGlucose(row.valueMgDl, unit),
    displayUnit: unit,
    converted: unit !== row.originalUnit,
    measuredAt: row.measuredAt.toISOString(),
    ...localRecordTime(row.measuredAt, settings.timezone),
    source: row.source,
    sourceRecordId: row.sourceRecordId,
    measurementType: row.measurementType,
    mealContext: row.mealContext,
    qualityStatus: row.qualityStatus,
    qualityFlags: row.qualityFlags,
    notes: row.notes,
    recordedAt: row.recordedAt.toISOString(),
    receivedAt: row.receivedAt.toISOString(),
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
    version: row.version,
    archivedAt: row.archivedAt?.toISOString() ?? null,
    alert: glucoseAlert(row.valueMgDl.toNumber()),
  };
}
async function requireHealth(userId: string) {
  await consentService.requireConsent(userId, "health_data_processing");
}
function canonical(value: number, unit: GlucoseUnit) {
  const result = canonicalGlucose(value, unit);
  if (result.lt(1) || result.gt(2000))
    throw unprocessable(
      "GLUCOSE_VALUE_OUT_OF_DOMAIN",
      "Nilai di luar batas masukan numerik aplikasi.",
    );
  return result;
}
export const glucoseService = {
  async create(userId: string, input: GlucoseInput) {
    await requireHealth(userId);
    const settings = await preferencesService.get(userId);
    const hash = createHash("sha256")
      .update(JSON.stringify(input))
      .digest("hex");
    try {
      const row = await prisma.$transaction(async (tx) => {
        const old = await glucoseRepository.find(userId, input.id, tx);
        if (old) {
          if (old.createHash !== hash)
            throw conflict(
              "IDEMPOTENCY_CONFLICT",
              "ID pengukuran sudah digunakan dengan isi berbeda.",
            );
          return old;
        }
        const value = canonical(input.originalValue, input.originalUnit);
        const saved = await tx.glucoseObservation.create({
          data: {
            ...input,
            userId,
            measuredAt: new Date(input.measuredAt),
            valueMgDl: value,
            createHash: hash,
            qualityFlags:
              input.qualityStatus === "needs_review" ? ["user_flagged"] : [],
          },
        });
        await recordAudit(tx, {
          userId,
          eventType: "glucose_recorded",
          metadata: { recordId: saved.id },
        });
        return saved;
      });
      return view(row, settings);
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === "P2002"
      ) {
        const old = await glucoseRepository.find(userId, input.id);
        if (old?.createHash === hash) return view(old, settings);
        throw conflict(
          "IDEMPOTENCY_CONFLICT",
          "ID pengukuran sudah digunakan.",
        );
      }
      throw error;
    }
  },
  async get(userId: string, id: string) {
    await requireHealth(userId);
    const [row, settings] = await Promise.all([
      glucoseRepository.find(userId, id),
      preferencesService.get(userId),
    ]);
    if (!row)
      throw notFound("GLUCOSE_NOT_FOUND", "Pengukuran tidak ditemukan.");
    return view(row, settings);
  },
  async update(userId: string, id: string, input: GlucosePatch) {
    await requireHealth(userId);
    const settings = await preferencesService.get(userId);
    const row = await prisma.$transaction(async (tx) => {
      const old = await glucoseRepository.find(userId, id, tx);
      if (!old)
        throw notFound("GLUCOSE_NOT_FOUND", "Pengukuran tidak ditemukan.");
      if (old.version !== input.expectedVersion)
        throw conflict(
          "VERSION_CONFLICT",
          "Pengukuran berubah. Muat ulang sebelum mengoreksi.",
        );
      const originalValue = input.originalValue ?? old.originalValue.toNumber();
      const originalUnit = (input.originalUnit ??
        old.originalUnit) as GlucoseUnit;
      const qualityStatus = old.source !== "manual_glucometer" && input.qualityStatus === "user_reported" ? "device_reported" : (input.qualityStatus ?? old.qualityStatus);
      const { expectedVersion, reason, archived, measuredAt, ...fields } =
        input;
      const changed = await tx.glucoseObservation.updateMany({
        where: { id, userId, version: expectedVersion },
        data: {
          ...fields,
          originalValue,
          originalUnit,
          valueMgDl: canonical(originalValue, originalUnit),
          measuredAt: measuredAt ? new Date(measuredAt) : undefined,
          qualityStatus,
          qualityFlags:
            qualityStatus === "needs_review" ? ["user_flagged"] : [],
          archivedAt:
            archived === undefined ? undefined : archived ? new Date() : null,
          version: { increment: 1 },
        },
      });
      if (changed.count !== 1)
        throw conflict(
          "VERSION_CONFLICT",
          "Pengukuran berubah. Muat ulang sebelum mengoreksi.",
        );
      await tx.recordRevision.create({
        data: {
          userId,
          glucoseId: id,
          version: old.version,
          reason,
          snapshot: JSON.parse(
            JSON.stringify(
              view(old, { ...settings, glucoseUnit: old.originalUnit }),
            ),
          ),
        },
      });
      await recordAudit(tx, {
        userId,
        eventType: archived ? "glucose_archived" : "glucose_corrected",
        metadata: { recordId: id, version: old.version + 1 },
      });
      return (await glucoseRepository.find(userId, id, tx))!;
    });
    return view(row, settings);
  },
  async revisions(userId: string, id: string) {
    await this.get(userId, id);
    return {
      items: await prisma.recordRevision.findMany({
        where: { userId, glucoseId: id },
        orderBy: { version: "desc" },
      }),
    };
  },
  async list(
    userId: string,
    query: { date?: string; cursor?: string; limit: number; archived: string },
  ) {
    await requireHealth(userId);
    const settings = await preferencesService.get(userId);
    return prisma.$transaction(
      async (tx) => {
        const ids = query.date
          ? await glucoseRepository.dateIds(
              userId,
              query.date,
              settings.timezone,
              tx,
              query.archived === "true",
            )
          : null;
        const anchor = query.cursor
          ? await glucoseRepository.find(userId, query.cursor, tx)
          : null;
        if (query.cursor && !anchor)
          throw notFound("CURSOR_NOT_FOUND", "Cursor tidak ditemukan.");
        const rows = await tx.glucoseObservation.findMany({
          where: {
            userId,
            archivedAt: query.archived === "true" ? { not: null } : null,
            ...(ids ? { id: { in: ids } } : {}),
            ...(anchor
              ? {
                  OR: [
                    { measuredAt: { lt: anchor.measuredAt } },
                    { measuredAt: anchor.measuredAt, id: { lt: anchor.id } },
                  ],
                }
              : {}),
          },
          orderBy: [{ measuredAt: "desc" }, { id: "desc" }],
          take: query.limit + 1,
        });
        const page = rows.slice(0, query.limit);
        return {
          items: page.map((row) => view(row, settings)),
          nextCursor: rows.length > query.limit ? page.at(-1)!.id : null,
          timezone: settings.timezone,
          displayUnit: settings.glucoseUnit,
        };
      },
      { isolationLevel: "RepeatableRead" },
    );
  },
  async daily(userId: string, date?: string) {
    await requireHealth(userId);
    await consentService.requireConsent(userId, "descriptive_summaries");
    const settings = await preferencesService.get(userId);
    const day =
      date ?? localRecordTime(new Date(), settings.timezone).localDate;
    const rows = await prisma.$transaction(
      async (tx) => {
        const ids = await glucoseRepository.dateIds(
          userId,
          day,
          settings.timezone,
          tx,
        );
        return tx.glucoseObservation.findMany({
          where: { userId, id: { in: ids } },
          orderBy: [{ measuredAt: "desc" }, { id: "desc" }],
        });
      },
      { isolationLevel: "RepeatableRead" },
    );
    const eligible = rows.filter(
      (row) => row.qualityStatus !== "needs_review",
    );
    const values = eligible.map((row) => row.valueMgDl);
    const mean =
      eligible.length >= 2
        ? values
            .reduce((sum, v) => sum.add(v), new Prisma.Decimal(0))
            .div(values.length)
        : null;
    return {
      date: day,
      timezone: settings.timezone,
      displayUnit: settings.glucoseUnit,
      count: rows.length,
      eligibleCount: eligible.length,
      reviewCount: rows.length - eligible.length,
      latest: rows[0] ? view(rows[0], settings) : null,
      mean: mean
        ? displayGlucose(mean, settings.glucoseUnit as GlucoseUnit)
        : null,
      minimum:
        eligible.length >= 2
          ? displayGlucose(
              Prisma.Decimal.min(...values),
              settings.glucoseUnit as GlucoseUnit,
            )
          : null,
      maximum:
        eligible.length >= 2
          ? displayGlucose(
              Prisma.Decimal.max(...values),
              settings.glucoseUnit as GlucoseUnit,
            )
          : null,
      analyticsState: eligible.length >= 2 ? "READY" : "INSUFFICIENT_DATA",
      computationVersion: "glucose-descriptive-v1",
      computedAt: new Date().toISOString(),
      freshness: "CURRENT",
      source: "mixed_by_record",
      measurementType: "per_record",
    };
  },
};
