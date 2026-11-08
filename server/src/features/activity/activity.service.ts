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
import {
  activityEnd,
  activityWeek,
  shiftActivityDate,
  summarizeActivities,
} from "./activity.model.ts";
import { activityRepository } from "./activity.repository.ts";
import type { ActivityInput, ActivityPatch } from "./activity.schema.ts";
type Row = NonNullable<Awaited<ReturnType<typeof activityRepository.find>>>;
type Settings = Awaited<ReturnType<typeof preferencesService.get>>;
function view(row: Row, settings: Settings) {
  return {
    id: row.id,
    activityType: row.activityType,
    startedAt: row.startedAt.toISOString(),
    endedAt: row.endedAt.toISOString(),
    durationMinutes: row.durationMinutes,
    distanceKm: row.distanceKm?.toNumber() ?? null,
    steps: row.steps,
    reportedIntensity: row.reportedIntensity,
    source: row.source,
    qualityStatus: row.qualityStatus,
    notes: row.notes,
    version: row.version,
    archivedAt: row.archivedAt?.toISOString() ?? null,
    recordedAt: row.recordedAt.toISOString(),
    receivedAt: row.receivedAt.toISOString(),
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
    ...localRecordTime(row.startedAt, settings.timezone),
    endLocalDate: localRecordTime(row.endedAt, settings.timezone).localDate,
    endLocalTime: localRecordTime(row.endedAt, settings.timezone).localTime,
  };
}
async function requireHealth(userId: string) {
  await consentService.requireConsent(userId, "health_data_processing");
}
function requireCompleted(startedAt: Date, duration: number) {
  const end = activityEnd(startedAt, duration);
  if (end.getTime() > Date.now() + 300000)
    throw unprocessable(
      "ACTIVITY_NOT_COMPLETED",
      "Waktu selesai tidak boleh di masa depan.",
    );
  return end;
}
const method = {
  computationVersion: "activity-reported-v1",
  freshness: "CURRENT",
  coverageStatus: "RECORDED_ONLY",
  source: "manual",
  attribution: "START_LOCAL_DATE",
  durationMethod: "SUM_REPORTED_SESSIONS",
};
export const activityService = {
  async create(userId: string, input: ActivityInput) {
    await requireHealth(userId);
    const settings = await preferencesService.get(userId);
    const hash = createHash("sha256")
      .update(JSON.stringify(input))
      .digest("hex");
    try {
      const row = await prisma.$transaction(async (tx) => {
        const old = await activityRepository.find(userId, input.id, tx);
        if (old) {
          if (old.createHash !== hash)
            throw conflict(
              "IDEMPOTENCY_CONFLICT",
              "ID aktivitas sudah digunakan dengan isi berbeda.",
            );
          return old;
        }
        const saved = await tx.activitySession.create({
          data: {
            ...input,
            userId,
            startedAt: new Date(input.startedAt),
            endedAt: requireCompleted(
              new Date(input.startedAt),
              input.durationMinutes,
            ),
            createHash: hash,
          },
        });
        await recordAudit(tx, {
          userId,
          eventType: "activity_recorded",
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
        const old = await activityRepository.find(userId, input.id);
        if (old?.createHash === hash) return view(old, settings);
        throw conflict("IDEMPOTENCY_CONFLICT", "ID aktivitas sudah digunakan.");
      }
      throw error;
    }
  },
  async get(userId: string, id: string) {
    await requireHealth(userId);
    const [row, settings] = await Promise.all([
      activityRepository.find(userId, id),
      preferencesService.get(userId),
    ]);
    if (!row)
      throw notFound("ACTIVITY_NOT_FOUND", "Aktivitas tidak ditemukan.");
    return view(row, settings);
  },
  async update(userId: string, id: string, input: ActivityPatch) {
    await requireHealth(userId);
    const settings = await preferencesService.get(userId);
    const row = await prisma.$transaction(async (tx) => {
      const old = await activityRepository.find(userId, id, tx);
      if (!old)
        throw notFound("ACTIVITY_NOT_FOUND", "Aktivitas tidak ditemukan.");
      if (old.version !== input.expectedVersion)
        throw conflict(
          "VERSION_CONFLICT",
          "Aktivitas berubah. Muat ulang sebelum mengoreksi.",
        );
      const { expectedVersion, reason, archived, startedAt, ...fields } = input;
      const start = startedAt ? new Date(startedAt) : old.startedAt;
      const duration = input.durationMinutes ?? old.durationMinutes;
      const changed = await tx.activitySession.updateMany({
        where: { id, userId, version: expectedVersion },
        data: {
          ...fields,
          startedAt: start,
          endedAt: requireCompleted(start, duration),
          archivedAt:
            archived === undefined ? undefined : archived ? new Date() : null,
          version: { increment: 1 },
        },
      });
      if (changed.count !== 1)
        throw conflict(
          "VERSION_CONFLICT",
          "Aktivitas berubah. Muat ulang sebelum mengoreksi.",
        );
      await tx.recordRevision.create({
        data: {
          userId,
          activityId: id,
          version: old.version,
          reason,
          snapshot: JSON.parse(JSON.stringify(view(old, settings))),
        },
      });
      await recordAudit(tx, {
        userId,
        eventType: archived ? "activity_archived" : "activity_corrected",
        metadata: { recordId: id, version: old.version + 1 },
      });
      return (await activityRepository.find(userId, id, tx))!;
    });
    return view(row, settings);
  },
  async revisions(userId: string, id: string) {
    await this.get(userId, id);
    return {
      items: await prisma.recordRevision.findMany({
        where: { userId, activityId: id },
        orderBy: { version: "desc" },
      }),
    };
  },
  async list(
    userId: string,
    q: { date?: string; cursor?: string; limit: number; archived: string },
  ) {
    await requireHealth(userId);
    const settings = await preferencesService.get(userId);
    return prisma.$transaction(
      async (tx) => {
        const ids = q.date
          ? await activityRepository.periodIds(
              userId,
              q.date,
              shiftActivityDate(q.date, 1),
              settings.timezone,
              tx,
              q.archived === "true",
            )
          : null;
        const anchor = q.cursor
          ? await activityRepository.find(userId, q.cursor, tx)
          : null;
        if (q.cursor && !anchor)
          throw notFound("CURSOR_NOT_FOUND", "Cursor tidak ditemukan.");
        const rows = await tx.activitySession.findMany({
          where: {
            userId,
            archivedAt: q.archived === "true" ? { not: null } : null,
            ...(ids ? { id: { in: ids } } : {}),
            ...(anchor
              ? {
                  OR: [
                    { startedAt: { lt: anchor.startedAt } },
                    { startedAt: anchor.startedAt, id: { lt: anchor.id } },
                  ],
                }
              : {}),
          },
          orderBy: [{ startedAt: "desc" }, { id: "desc" }],
          take: q.limit + 1,
        });
        const page = rows.slice(0, q.limit);
        return {
          items: page.map((r) => view(r, settings)),
          nextCursor: rows.length > q.limit ? page.at(-1)!.id : null,
          timezone: settings.timezone,
        };
      },
      { isolationLevel: "RepeatableRead" },
    );
  },
  async period(userId: string, date: string | undefined, weekly: boolean) {
    await requireHealth(userId);
    await consentService.requireConsent(userId, "descriptive_summaries");
    const settings = await preferencesService.get(userId);
    const day =
      date ?? localRecordTime(new Date(), settings.timezone).localDate;
    const bounds = weekly
      ? activityWeek(day, settings.locale)
      : { startDate: day, endDate: shiftActivityDate(day, 1), firstDay: null };
    const rows = await prisma.$transaction(
      async (tx) => {
        const ids = await activityRepository.periodIds(
          userId,
          bounds.startDate,
          bounds.endDate,
          settings.timezone,
          tx,
        );
        return tx.activitySession.findMany({
          where: { userId, id: { in: ids } },
          orderBy: [{ startedAt: "desc" }, { id: "desc" }],
        });
      },
      { isolationLevel: "RepeatableRead" },
    );
    const summary = summarizeActivities(rows);
    const days = Array.from({ length: weekly ? 7 : 1 }, (_, i) => {
      const localDate = shiftActivityDate(bounds.startDate, i);
      return {
        date: localDate,
        ...summarizeActivities(
          rows.filter(
            (row) =>
              localRecordTime(row.startedAt, settings.timezone).localDate ===
              localDate,
          ),
        ),
      };
    });
    return {
      ...bounds,
      date: day,
      timezone: settings.timezone,
      locale: settings.locale,
      ...summary,
      days,
      activeDays: days.filter((d) => d.eligibleCount > 0).length,
      latest: rows[0] ? view(rows[0], settings) : null,
      analyticsState: summary.eligibleCount ? "READY" : "INSUFFICIENT_DATA",
      computedAt: new Date().toISOString(),
      ...method,
    };
  },
  daily(userId: string, date?: string) {
    return this.period(userId, date, false);
  },
  weekly(userId: string, date?: string) {
    return this.period(userId, date, true);
  },
};
