import { prisma } from "../../infrastructure/database/prisma.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { ACTIVITY_COUNTED_QUALITY } from "../activity/activity.model.ts";
import { zonedToUtc } from "../medication/medication.model.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { aggregateDays, datesBetween, type DayFacts, PROJECTION_VERSION } from "./daily-facts.model.ts";

const DAY = 86_400_000;
const asDate = (d: string) => new Date(d + "T00:00:00Z");
const iso = (d: Date) => d.toISOString().slice(0, 10);
const addDays = (d: string, n: number) => iso(new Date(Date.parse(d + "T00:00:00Z") + n * DAY));

async function computeRange(userId: string, dates: string[], tz: string): Promise<Map<string, DayFacts>> {
  const from = dates[0]!, to = dates[dates.length - 1]!;
  const lo = zonedToUtc(from, "00:00", tz), hi = zonedToUtc(addDays(to, 1), "00:00", tz);
  const where = { userId, archivedAt: null };
  const [sessions, meals, glucose, intakes, checkins, steps, sleep] = await Promise.all([
    prisma.activitySession.findMany({ where: { ...where, qualityStatus: { in: [...ACTIVITY_COUNTED_QUALITY] }, startedAt: { gte: lo, lt: hi } }, select: { startedAt: true, durationMinutes: true, source: true } }),
    prisma.mealLog.findMany({ where: { ...where, consumedAt: { gte: lo, lt: hi } }, select: { consumedAt: true, category: true } }),
    prisma.glucoseObservation.findMany({ where: { ...where, measuredAt: { gte: lo, lt: hi } }, select: { measuredAt: true } }),
    prisma.medicationIntake.findMany({ where: { ...where, status: "taken", eventAt: { gte: lo, lt: hi } }, select: { eventAt: true } }),
    prisma.goalCheckin.findMany({ where: { ...where, eventAt: { gte: lo, lt: hi } }, select: { eventAt: true } }),
    prisma.dailySteps.findMany({ where: { userId, localDate: { gte: asDate(from), lte: asDate(to) } }, select: { localDate: true, steps: true, source: true } }),
    prisma.sleepSession.findMany({ where: { userId, endedAt: { gte: lo, lt: hi } }, select: { startedAt: true, endedAt: true, durationMinutes: true, source: true } }),
  ]);
  return aggregateDays(
    dates,
    {
      sessions,
      meals: meals.map((m) => ({ at: m.consumedAt, category: m.category })),
      glucose: glucose.map((g) => ({ at: g.measuredAt })),
      intakes: intakes.map((i) => ({ at: i.eventAt })),
      checkins: checkins.map((c) => ({ at: c.eventAt })),
      steps: steps.map((s) => ({ localDate: iso(s.localDate), steps: s.steps, source: s.source })),
      sleep,
    },
    (d) => localRecordTime(d, tz).localDate,
  );
}

function toRow(userId: string, tz: string, f: DayFacts, now: Date) {
  return {
    userId,
    localDate: asDate(f.localDate),
    timezone: tz,
    activeMinutes: f.activeMinutes,
    activeMinutesManual: f.activeMinutesManual,
    activeMinutesDevice: f.activeMinutesDevice,
    sessionCount: f.sessionCount,
    longestSessionMinutes: f.longestSessionMinutes,
    steps: f.steps,
    stepsSources: f.stepsSources,
    sleepMinutes: f.sleepMinutes,
    mealsLogged: f.mealsLogged,
    mealCategories: f.mealCategories,
    glucoseChecks: f.glucoseChecks,
    medicationConfirmed: f.medicationConfirmed,
    goalCheckins: f.goalCheckins,
    sources: f.sources,
    dirty: false,
    computationVersion: PROJECTION_VERSION,
    computedAt: now,
  };
}

type FactRow = Awaited<ReturnType<typeof prisma.dailyBehaviorFact.findMany>>[number];
const fromRow = (r: FactRow): DayFacts => ({
  localDate: iso(r.localDate),
  activeMinutes: r.activeMinutes,
  activeMinutesManual: r.activeMinutesManual,
  activeMinutesDevice: r.activeMinutesDevice,
  sessionCount: r.sessionCount,
  longestSessionMinutes: r.longestSessionMinutes,
  steps: r.steps,
  stepsSources: r.stepsSources,
  sleepMinutes: r.sleepMinutes,
  mealsLogged: r.mealsLogged,
  mealCategories: r.mealCategories,
  glucoseChecks: r.glucoseChecks,
  medicationConfirmed: r.medicationConfirmed,
  goalCheckins: r.goalCheckins,
  sources: r.sources,
});

export const dailyFacts = {
  async rebuild(userId: string, from: string, to: string, tz?: string, now = new Date()) {
    const zone = tz ?? (await preferencesService.get(userId)).timezone;
    const dates = datesBetween(from, to);
    if (!dates.length) return new Map<string, DayFacts>();
    const facts = await computeRange(userId, dates, zone);
    await prisma.$transaction(
      [...facts.values()].map((f) => {
        const data = toRow(userId, zone, f, now);
        return prisma.dailyBehaviorFact.upsert({ where: { userId_localDate: { userId, localDate: data.localDate } }, create: data, update: data });
      }),
    );
    return facts;
  },

  async ensure(userId: string, from: string, to: string, tz?: string): Promise<Map<string, DayFacts>> {
    const zone = tz ?? (await preferencesService.get(userId)).timezone;
    const dates = datesBetween(from, to);
    if (!dates.length) return new Map();
    const rows = await prisma.dailyBehaviorFact.findMany({ where: { userId, localDate: { gte: asDate(from), lte: asDate(to) } } });
    const fresh = new Map(rows.filter((r) => !r.dirty && r.timezone === zone && r.computationVersion === PROJECTION_VERSION).map((r) => [iso(r.localDate), fromRow(r)]));
    const stale = dates.filter((d) => !fresh.has(d));
    if (stale.length) {
      const rebuilt = await this.rebuild(userId, stale[0]!, stale[stale.length - 1]!, zone);
      for (const d of stale) fresh.set(d, rebuilt.get(d)!);
    }
    return new Map(dates.map((d) => [d, fresh.get(d)!]));
  },

  async list(userId: string, from: string, to: string, tz?: string): Promise<DayFacts[]> {
    return [...(await this.ensure(userId, from, to, tz)).values()];
  },

  async stored(userId: string, from: string, to: string) {
    return (await prisma.dailyBehaviorFact.findMany({ where: { userId, localDate: { gte: asDate(from), lte: asDate(to) } }, orderBy: { localDate: "asc" } })).map(fromRow);
  },

  async onRecordEvent(userId: string, localDates: string[]) {
    if (!localDates.length) return;
    const sorted = [...new Set(localDates)].sort();
    const rows = await prisma.dailyBehaviorFact.findMany({ where: { userId, localDate: { in: sorted.map(asDate) } }, select: { localDate: true } });
    if (!rows.length) return;
    const known = rows.map((r) => iso(r.localDate)).sort();
    await this.rebuild(userId, known[0]!, known[known.length - 1]!);
  },
};
