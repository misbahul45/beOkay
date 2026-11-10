import { prisma } from "../../infrastructure/database/prisma.ts";
import { shiftActivityDate } from "../activity/activity.model.ts";
import { activityService } from "../activity/activity.service.ts";
import { consentService } from "../consent/consent.service.ts";
import { goalsService } from "../goals/goals.service.ts";
import { isoWeekday } from "../medication/medication.model.ts";
import { medicationService } from "../medication/medication.service.ts";
import { nutritionService } from "../nutrition/nutrition.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { buildContextualInsights, loggingStreak, type ContextSnapshot } from "./contextual.model.ts";

const DAY = 86_400_000;

export const contextualService = {
  async get(userId: string, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    await consentService.requireConsent(userId, "descriptive_summaries");
    const { timezone } = await preferencesService.get(userId);
    const local = localRecordTime(now, timezone);
    const today = local.localDate;
    const since = new Date(now.getTime() - 20 * DAY);

    const [med, meal, goals, lastGlucose, glucoseTotal, week] = await Promise.all([
      medicationService.today(userId, today),
      nutritionService.daily(userId, today),
      goalsService.list(userId, { status: "active", limit: 20 }),
      prisma.glucoseObservation.findFirst({ where: { userId, archivedAt: null }, orderBy: { measuredAt: "desc" }, select: { measuredAt: true } }),
      prisma.glucoseObservation.count({ where: { userId, archivedAt: null } }),
      activityService.period(userId, today, true),
    ]);
    const [prevWeek, weekBefore] = await Promise.all([
      activityService.period(userId, shiftActivityDate(week.startDate, -7), true),
      activityService.period(userId, shiftActivityDate(week.startDate, -14), true),
    ]);

    // Hari-hari (lokal) dengan paling sedikit satu catatan, 20 hari terakhir.
    const [meals, glucose, activities, intakes] = await Promise.all([
      prisma.mealLog.findMany({ where: { userId, archivedAt: null, consumedAt: { gte: since } }, select: { consumedAt: true } }),
      prisma.glucoseObservation.findMany({ where: { userId, archivedAt: null, measuredAt: { gte: since } }, select: { measuredAt: true } }),
      prisma.activitySession.findMany({ where: { userId, archivedAt: null, startedAt: { gte: since } }, select: { startedAt: true } }),
      prisma.medicationIntake.findMany({ where: { userId, archivedAt: null, createdAt: { gte: since } }, select: { createdAt: true } }),
    ]);
    const days = [...meals.map((r) => r.consumedAt), ...glucose.map((r) => r.measuredAt), ...activities.map((r) => r.startedAt), ...intakes.map((r) => r.createdAt)].map((d) => localRecordTime(d, timezone).localDate);

    const pastDue = med.items.filter((i) => i.status === "unknown" && new Date(i.scheduledAt).getTime() < now.getTime()).length;
    const snapshot: ContextSnapshot = {
      localDate: today,
      localHour: Number(local.localTime.slice(0, 2)),
      isoWeekday: isoWeekday(today),
      medication: { scheduledPastDueUnknown: pastDue, scheduledTotal: med.items.length },
      mealsToday: meal.mealCount,
      glucose: {
        totalRecords: glucoseTotal,
        daysSinceLast: lastGlucose ? Math.round((Date.parse(today + "T00:00:00Z") - Date.parse(localRecordTime(lastGlucose.measuredAt, timezone).localDate + "T00:00:00Z")) / DAY) : null,
      },
      activity: { lastWeekActiveDays: prevWeek.activeDays, weekBeforeActiveDays: weekBefore.activeDays },
      goals: (goals.items as any[]).map((g) => ({ id: g.id, title: g.title, period: g.period, value: g.progress?.value ?? null, target: g.targetValue })),
      loggingStreakDays: loggingStreak(days, today),
    };
    return { date: today, timezone, ...buildContextualInsights(snapshot), computedAt: now.toISOString() };
  },
};
