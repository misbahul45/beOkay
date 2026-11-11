import { prisma } from "../../infrastructure/database/prisma.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { ACTIVITY_COUNTED_QUALITY, shiftActivityDate } from "../activity/activity.model.ts";
import { consentService } from "../consent/consent.service.ts";
import { displayGlucose } from "../glucose/glucose.model.ts";
import { isoWeekday, occurrencesFor } from "../medication/medication.model.ts";
import { nutritionService } from "../nutrition/nutrition.service.ts";
import type { GlucoseUnit } from "../preferences/glucose-units.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { NUTRIENTS, buildStatistics, type Nutrient, type StatDay } from "./statistics.model.ts";

export const STATISTICS_PERIODS = [7, 14, 30, 90] as const;

const emptyNutrients = () => Object.fromEntries(NUTRIENTS.map((n) => [n, { value: null, knownItems: 0, totalItems: 0 }])) as StatDay["nutrients"];

export const statisticsService = {
  async get(userId: string, days: number, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    await consentService.requireConsent(userId, "descriptive_summaries");
    const { timezone, glucoseUnit } = await preferencesService.get(userId);
    const today = localRecordTime(now, timezone).localDate;
    const dates = Array.from({ length: days * 2 }, (_, i) => shiftActivityDate(today, i - (days * 2 - 1)));
    const from = new Date(`${shiftActivityDate(dates[0]!, -1)}T00:00:00Z`);
    const to = new Date(`${shiftActivityDate(today, 2)}T00:00:00Z`);
    const local = (d: Date) => localRecordTime(d, timezone).localDate;

    const [meals, activity, glucose, regimens] = await Promise.all([
      nutritionService.mealsBetween(userId, from, to, timezone),
      prisma.activitySession.findMany({
        where: { userId, archivedAt: null, qualityStatus: { in: [...ACTIVITY_COUNTED_QUALITY] }, startedAt: { gte: from, lt: to } },
        select: { startedAt: true, durationMinutes: true },
      }),
      prisma.glucoseObservation.findMany({
        where: { userId, archivedAt: null, qualityStatus: "user_reported", measuredAt: { gte: from, lt: to } },
        select: { measuredAt: true, valueMgDl: true, mealContext: true },
      }),
      prisma.medicationRegimen.findMany({ where: { userId, status: "active" }, include: { schedules: true } }),
    ]);

    const byDate = new Map<string, StatDay>(
      dates.map((date) => [date, { date, isoWeekday: isoWeekday(date), meals: 0, nutrients: emptyNutrients(), activityMinutes: null, activitySessions: 0, glucose: [], med: { scheduled: 0, taken: 0, skipped: 0 } }]),
    );

    for (const m of meals) {
      const d = byDate.get(m.localDate);
      if (!d) continue;
      d.meals += 1;
      for (const item of m.items) {
        for (const n of NUTRIENTS) {
          const slot = d.nutrients[n as Nutrient];
          slot.totalItems += 1;
          const v = item.nutrition[n];
          if (v !== null && v !== undefined) {
            slot.knownItems += 1;
            slot.value = (slot.value ?? 0) + v;
          }
        }
      }
    }
    for (const a of activity) {
      const d = byDate.get(local(a.startedAt));
      if (!d) continue;
      d.activityMinutes = (d.activityMinutes ?? 0) + a.durationMinutes;
      d.activitySessions += 1;
    }
    for (const g of glucose) {
      const d = byDate.get(local(g.measuredAt));
      if (d) d.glucose.push({ value: displayGlucose(g.valueMgDl, glucoseUnit as GlucoseUnit), context: g.mealContext });
    }

    const occurrences = dates.flatMap((date) =>
      occurrencesFor(
        date,
        regimens
          .filter((r) => (!r.startDate || r.startDate.toISOString().slice(0, 10) <= date) && (!r.endDate || r.endDate.toISOString().slice(0, 10) >= date))
          .flatMap((r) => r.schedules),
      )
        .filter((o) => o.scheduledAt.getTime() <= now.getTime())
        .map((o) => ({ ...o, date })),
    );
    const intakes = occurrences.length
      ? await prisma.medicationIntake.findMany({
          where: { userId, archivedAt: null, status: { in: ["taken", "skipped"] }, scheduleId: { in: [...new Set(occurrences.map((o) => o.scheduleId))] }, scheduledAt: { gte: from, lt: to } },
          select: { scheduleId: true, scheduledAt: true, status: true },
        })
      : [];
    const confirmed = new Map(intakes.map((i) => [`${i.scheduleId}|${i.scheduledAt?.getTime()}`, i.status]));
    for (const o of occurrences) {
      const d = byDate.get(o.date)!;
      d.med.scheduled += 1;
      const status = confirmed.get(`${o.scheduleId}|${o.scheduledAt.getTime()}`);
      if (status === "taken") d.med.taken += 1;
      if (status === "skipped") d.med.skipped += 1;
    }

    return { timezone, ...buildStatistics(dates.map((d) => byDate.get(d)!), { glucoseUnit, computedAt: now }) };
  },
};
