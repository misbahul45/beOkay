import { prisma } from "../../infrastructure/database/prisma.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { consentService } from "../consent/consent.service.ts";
import { zonedToUtc } from "../medication/medication.model.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { datesBetween } from "../projections/daily-facts.model.ts";
import { addDays, assessSleep, assessSteps, assessWorkouts, type DayQuality, QUALITY_VERSION, summarize, type Signal } from "./quality.model.ts";

const iso = (d: Date) => d.toISOString().slice(0, 10);

export const deviceQualityService = {
  async assess(userId: string, days = 14, now = new Date()) {
    const { timezone } = await preferencesService.get(userId);
    const today = localRecordTime(now, timezone).localDate;
    const from = addDays(today, -(days - 1));
    const lo = zonedToUtc(from, "00:00", timezone), hi = zonedToUtc(addDays(today, 1), "00:00", timezone);
    const [prefs, steps, sleep, workouts] = await Promise.all([
      prisma.deviceImportPreference.findUnique({ where: { userId } }),
      prisma.dailySteps.findMany({ where: { userId, localDate: { gte: new Date(from + "T00:00:00Z"), lte: new Date(today + "T00:00:00Z") } } }),
      prisma.sleepSession.findMany({ where: { userId, endedAt: { gte: lo, lt: hi } } }),
      prisma.activitySession.findMany({ where: { userId, archivedAt: null, source: { not: "manual" }, startedAt: { gte: lo, lt: hi } } }),
    ]);
    const lastSync = (xs: Date[]) => (xs.length ? new Date(Math.max(...xs.map((d) => d.getTime()))) : null);
    const lastSyncAt = {
      steps: lastSync(steps.map((s) => s.syncedAt)),
      sleep: lastSync(sleep.map((s) => s.createdAt)),
      workouts: lastSync(workouts.map((w) => w.receivedAt)),
    };
    const local = (d: Date) => localRecordTime(d, timezone).localDate;
    const dates = datesBetween(from, today);
    const perDay: Record<Signal, DayQuality[]> = { steps: [], sleep: [], workouts: [] };
    for (const d of dates) {
      perDay.steps.push(assessSteps(d, steps.filter((s) => iso(s.localDate) === d).map((s) => ({ localDate: d, steps: s.steps, dataOrigin: s.dataOrigin, syncedAt: s.syncedAt })), { today, now, connected: Boolean(prefs?.steps), lastSyncAt: lastSyncAt.steps }));
      perDay.sleep.push(assessSleep(d, sleep.filter((s) => local(s.endedAt) === d).map((s) => ({ startedAt: s.startedAt, endedAt: s.endedAt, dataOrigin: s.dataOrigin, createdAt: s.createdAt, localDate: d })), { today, now, connected: Boolean(prefs?.sleep), lastSyncAt: lastSyncAt.sleep }));
      perDay.workouts.push(assessWorkouts(d, workouts.filter((w) => local(w.startedAt) === d).map((w) => ({ startedAt: w.startedAt, durationMinutes: w.durationMinutes, dataOrigin: w.dataOrigin, receivedAt: w.receivedAt, qualityStatus: w.qualityStatus, localDate: d })), { today, now, connected: Boolean(prefs?.workouts), lastSyncAt: lastSyncAt.workouts }));
    }
    return { version: QUALITY_VERSION, timezone, from, to: today, perDay, summary: (Object.keys(perDay) as Signal[]).map((s) => summarize(s, perDay[s])), lastSyncAt: { steps: lastSyncAt.steps?.toISOString() ?? null, sleep: lastSyncAt.sleep?.toISOString() ?? null, workouts: lastSyncAt.workouts?.toISOString() ?? null } };
  },

  async status(userId: string, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    const [q, prefs, deviceConsent] = await Promise.all([
      this.assess(userId, 14, now),
      prisma.deviceImportPreference.findUnique({ where: { userId } }),
      consentService.hasConsent(userId, "device_data_coaching"),
    ]);
    const origins = [...new Set(Object.values(q.perDay).flat().flatMap((d) => d.origins))].filter((o) => o !== "unknown").sort();
    return {
      version: q.version,
      window: { from: q.from, to: q.to, timezone: q.timezone },
      permissions: { workouts: Boolean(prefs?.workouts), steps: Boolean(prefs?.steps), weight: Boolean(prefs?.weight), glucose: Boolean(prefs?.glucose), sleep: Boolean(prefs?.sleep) },
      usedForCoaching: deviceConsent,
      lastSyncAt: q.lastSyncAt,
      origins,
      signals: q.summary,
      days: q.perDay,
      notice: "Hari tanpa data perangkat tidak pernah dianggap tidak aktif. Angka dari perangkat adalah perkiraan.",
    };
  },
};
