import { createHash } from "node:crypto";
import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { conflict, notFound, unprocessable } from "../../shared/errors/app-error.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { consentService } from "../consent/consent.service.ts";
import { zonedToUtc } from "../medication/medication.model.ts";
import { ACTIVITY_COUNTED_QUALITY } from "../activity/activity.model.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { goalBounds, summarizeGoal, type GoalSource } from "./goals.model.ts";
import { goalsRepository as repo } from "./goals.repository.ts";
import type { CheckinInput, CheckinPatch, GoalInput, GoalPatch } from "./goals.schema.ts";

const day = (d: Date | null) => d?.toISOString().slice(0, 10) ?? null;
const sha = (v: unknown) => createHash("sha256").update(JSON.stringify(v)).digest("hex");
const asDate = (d: string | null | undefined) => (d ? new Date(d + "T00:00:00Z") : d === null ? null : undefined);
const requireHealth = (userId: string) => consentService.requireConsent(userId, "health_data_processing");
const isUnique = (e: unknown) => e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002";
type Goal = NonNullable<Awaited<ReturnType<typeof repo.find>>>;
type Checkin = NonNullable<Awaited<ReturnType<typeof repo.checkin>>>;
const goalView = (g: Goal) => ({ id: g.id, title: g.title, goalType: g.goalType, targetValue: g.targetValue.toNumber(), period: g.period, startDate: day(g.startDate), endDate: day(g.endDate), status: g.status, version: g.version, createdAt: g.createdAt.toISOString(), updatedAt: g.updatedAt.toISOString() });
const checkinView = (c: Checkin, timezone: string) => ({ id: c.id, goalId: c.goalId, eventAt: c.eventAt.toISOString(), status: c.status, value: c.value.toNumber(), notes: c.notes, version: c.version, archivedAt: c.archivedAt?.toISOString() ?? null, createdAt: c.createdAt.toISOString(), updatedAt: c.updatedAt.toISOString(), ...localRecordTime(c.eventAt, timezone) });
const needGoal = async (userId: string, id: string, db?: Prisma.TransactionClient) => {
  const g = await repo.find(userId, id, db);
  if (!g) throw notFound("GOAL_NOT_FOUND", "Tujuan tidak ditemukan.");
  return g;
};

/** Qualifying records for the period, read from the authoritative domains so corrections and archiving recalculate progress. */
async function sourcesFor(userId: string, g: Goal, from: Date, to: Date, tz: string): Promise<GoalSource[]> {
  const localDay = (d: Date) => localRecordTime(d, tz).localDate;
  switch (g.goalType) {
    case "manual_checkins": {
      const rows = await prisma.goalCheckin.findMany({ where: { userId, goalId: g.id, archivedAt: null, eventAt: { gte: from, lt: to } } });
      return rows.map((r) => ({ date: localDay(r.eventAt), status: r.status, value: r.value.toNumber() }));
    }
    case "activity_minutes":
    case "walking_sessions": {
      const rows = await prisma.activitySession.findMany({ where: { userId, archivedAt: null, qualityStatus: { in: [...ACTIVITY_COUNTED_QUALITY] }, startedAt: { gte: from, lt: to }, ...(g.goalType === "walking_sessions" ? { activityType: "walking" } : {}) } });
      return rows.map((r) => ({ date: localDay(r.startedAt), value: g.goalType === "activity_minutes" ? r.durationMinutes : 1 }));
    }
    case "daily_steps": {
      const rows = await prisma.dailySteps.findMany({ where: { userId, localDate: { gte: new Date(localDay(from) + "T00:00:00Z"), lt: new Date(localDay(to) + "T00:00:00Z") } } });
      return rows.map((r) => ({ date: r.localDate.toISOString().slice(0, 10), value: r.steps }));
    }
    case "record_meals": {
      const rows = await prisma.mealLog.findMany({ where: { userId, archivedAt: null, consumedAt: { gte: from, lt: to } }, select: { consumedAt: true } });
      return rows.map((r) => ({ date: localDay(r.consumedAt) }));
    }
    default: {
      const rows = await prisma.glucoseObservation.findMany({ where: { userId, archivedAt: null, qualityStatus: { not: "needs_review" }, measuredAt: { gte: from, lt: to } }, select: { measuredAt: true } });
      return rows.map((r) => ({ date: localDay(r.measuredAt) }));
    }
  }
}

export const goalsService = {
  async create(userId: string, input: GoalInput) {
    await requireHealth(userId);
    const hash = sha(input);
    try {
      const row = await prisma.$transaction(async (tx) => {
        const old = await repo.find(userId, input.id, tx);
        if (old) {
          if (old.createHash !== hash) throw conflict("IDEMPOTENCY_CONFLICT", "ID tujuan sudah digunakan dengan isi berbeda.");
          return old;
        }
        const saved = await tx.behaviorGoal.create({ data: { ...input, startDate: asDate(input.startDate)!, endDate: asDate(input.endDate) ?? null, userId, createHash: hash } });
        await recordAudit(tx, { userId, eventType: "goal_created", metadata: { recordId: saved.id } });
        return saved;
      });
      return goalView(row);
    } catch (e) {
      if (isUnique(e)) {
        const old = await repo.find(userId, input.id);
        if (old?.createHash === hash) return goalView(old);
        throw conflict("IDEMPOTENCY_CONFLICT", "ID tujuan sudah digunakan.");
      }
      throw e;
    }
  },
  async list(userId: string, q: { status?: string; cursor?: string; limit: number }) {
    await requireHealth(userId);
    const anchor = q.cursor ? await repo.find(userId, q.cursor) : null;
    if (q.cursor && !anchor) throw notFound("CURSOR_NOT_FOUND", "Cursor tidak ditemukan.");
    const rows = await prisma.behaviorGoal.findMany({ where: { userId, ...(q.status ? { status: q.status } : { status: { not: "archived" } }), ...(anchor ? { OR: [{ createdAt: { lt: anchor.createdAt } }, { createdAt: anchor.createdAt, id: { lt: anchor.id } }] } : {}) }, orderBy: [{ createdAt: "desc" }, { id: "desc" }], take: q.limit + 1 });
    const page = rows.slice(0, q.limit);
    const progress = await Promise.all(page.map((g) => this.progress(userId, g)));
    return { items: page.map((g, i) => ({ ...goalView(g), progress: progress[i] })), nextCursor: rows.length > q.limit ? page.at(-1)!.id : null };
  },
  async get(userId: string, id: string) {
    await requireHealth(userId);
    const g = await needGoal(userId, id);
    return { ...goalView(g), progress: await this.progress(userId, g) };
  },
  /** Progress for the current calendar period in the user's timezone. Missing data is "no records", never "failed". */
  async progress(userId: string, g: Goal, date?: string) {
    const settings = await preferencesService.get(userId);
    const today = date ?? localRecordTime(new Date(), settings.timezone).localDate;
    const b = goalBounds(today, g.period, settings.locale, day(g.startDate)!, day(g.endDate));
    const from = zonedToUtc(b.sourceStartDate, "00:00", settings.timezone);
    const to = zonedToUtc(b.sourceEndDate, "00:00", settings.timezone);
    const rows = from < to ? await sourcesFor(userId, g, from, to, settings.timezone) : [];
    return { ...summarizeGoal(g.goalType, g.targetValue.toNumber(), rows), periodStart: b.startDate, periodEnd: b.endDate, timezone: settings.timezone, status: g.status, computationVersion: "goal-progress-v1", computedAt: new Date().toISOString() };
  },
  async update(userId: string, id: string, input: GoalPatch) {
    await requireHealth(userId);
    const row = await prisma.$transaction(async (tx) => {
      const old = await needGoal(userId, id, tx);
      if (old.version !== input.expectedVersion) throw conflict("VERSION_CONFLICT", "Tujuan berubah. Muat ulang sebelum mengubah.");
      const { expectedVersion, reason, startDate, endDate, ...fields } = input;
      const s = startDate ?? day(old.startDate)!, e = endDate === undefined ? day(old.endDate) : endDate;
      if (e && e < s) throw unprocessable("INVALID_DATE_RANGE", "Tanggal selesai mendahului tanggal mulai.");
      const changed = await tx.behaviorGoal.updateMany({ where: { id, userId, version: expectedVersion }, data: { ...fields, ...(startDate ? { startDate: asDate(startDate)! } : {}), ...(endDate !== undefined ? { endDate: asDate(endDate) ?? null } : {}), version: { increment: 1 } } });
      if (changed.count !== 1) throw conflict("VERSION_CONFLICT", "Tujuan berubah. Muat ulang sebelum mengubah.");
      await tx.recordRevision.create({ data: { userId, goalId: id, version: old.version, reason, snapshot: JSON.parse(JSON.stringify(goalView(old))) } });
      await recordAudit(tx, { userId, eventType: "goal_updated", metadata: { recordId: id, version: old.version + 1 } });
      return (await repo.find(userId, id, tx))!;
    });
    return goalView(row);
  },

  async createCheckin(userId: string, goalId: string, input: CheckinInput) {
    await requireHealth(userId);
    const settings = await preferencesService.get(userId);
    const hash = sha({ ...input, goalId });
    try {
      const row = await prisma.$transaction(async (tx) => {
        const old = await tx.goalCheckin.findFirst({ where: { id: input.id, userId } });
        if (old) {
          if (old.createHash !== hash) throw conflict("IDEMPOTENCY_CONFLICT", "ID check-in sudah digunakan dengan isi berbeda.");
          return old;
        }
        const goal = await needGoal(userId, goalId, tx);
        if (goal.goalType !== "manual_checkins") throw unprocessable("CHECKIN_NOT_SUPPORTED", "Tujuan ini dihitung otomatis dari catatan, bukan check-in manual.");
        const saved = await tx.goalCheckin.create({ data: { ...input, eventAt: new Date(input.eventAt), goalId, userId, createHash: hash } });
        await recordAudit(tx, { userId, eventType: "goal_checkin_recorded", metadata: { recordId: saved.id } });
        return saved;
      });
      return checkinView(row, settings.timezone);
    } catch (e) {
      if (isUnique(e)) throw conflict("IDEMPOTENCY_CONFLICT", "ID check-in sudah digunakan.");
      throw e;
    }
  },
  async listCheckins(userId: string, goalId: string, q: { cursor?: string; limit: number; archived: string }) {
    await requireHealth(userId);
    await needGoal(userId, goalId);
    const settings = await preferencesService.get(userId);
    const anchor = q.cursor ? await repo.checkin(userId, goalId, q.cursor) : null;
    if (q.cursor && !anchor) throw notFound("CURSOR_NOT_FOUND", "Cursor tidak ditemukan.");
    const rows = await prisma.goalCheckin.findMany({ where: { userId, goalId, archivedAt: q.archived === "true" ? { not: null } : null, ...(anchor ? { OR: [{ eventAt: { lt: anchor.eventAt } }, { eventAt: anchor.eventAt, id: { lt: anchor.id } }] } : {}) }, orderBy: [{ eventAt: "desc" }, { id: "desc" }], take: q.limit + 1 });
    const page = rows.slice(0, q.limit);
    return { items: page.map((r) => checkinView(r, settings.timezone)), nextCursor: rows.length > q.limit ? page.at(-1)!.id : null, timezone: settings.timezone };
  },
  async updateCheckin(userId: string, goalId: string, id: string, input: CheckinPatch) {
    await requireHealth(userId);
    const settings = await preferencesService.get(userId);
    const row = await prisma.$transaction(async (tx) => {
      const old = await repo.checkin(userId, goalId, id, tx);
      if (!old) throw notFound("CHECKIN_NOT_FOUND", "Check-in tidak ditemukan.");
      if (old.version !== input.expectedVersion) throw conflict("VERSION_CONFLICT", "Check-in berubah. Muat ulang sebelum mengoreksi.");
      const { expectedVersion, reason, archived, eventAt, ...fields } = input;
      const changed = await tx.goalCheckin.updateMany({ where: { id, userId, version: expectedVersion }, data: { ...fields, ...(eventAt ? { eventAt: new Date(eventAt) } : {}), archivedAt: archived === undefined ? undefined : archived ? new Date() : null, version: { increment: 1 } } });
      if (changed.count !== 1) throw conflict("VERSION_CONFLICT", "Check-in berubah. Muat ulang sebelum mengoreksi.");
      await tx.recordRevision.create({ data: { userId, checkinId: id, version: old.version, reason, snapshot: JSON.parse(JSON.stringify(checkinView(old, settings.timezone))) } });
      await recordAudit(tx, { userId, eventType: archived ? "goal_checkin_archived" : "goal_checkin_corrected", metadata: { recordId: id, version: old.version + 1 } });
      return (await repo.checkin(userId, goalId, id, tx))!;
    });
    return checkinView(row, settings.timezone);
  },
};
