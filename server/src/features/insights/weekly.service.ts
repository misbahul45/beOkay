import { prisma } from "../../infrastructure/database/prisma.ts";
import { activityService } from "../activity/activity.service.ts";
import { shiftActivityDate } from "../activity/activity.model.ts";
import { glucoseService } from "../glucose/glucose.service.ts";
import { goalsService } from "../goals/goals.service.ts";
import { medicationService } from "../medication/medication.service.ts";
import { nutritionService } from "../nutrition/nutrition.service.ts";
import { summarizeWeek, type WeekDay } from "./weekly.model.ts";

export const COMPUTATION_VERSION = "weekly-cross-domain-v1";

export const weeklyService = {
  async get(userId: string, date?: string) {
    const act = await activityService.period(userId, date, true);
    const dates = Array.from({ length: 7 }, (_, i) => shiftActivityDate(act.startDate, i));
    const days: WeekDay[] = await Promise.all(
      dates.map(async (d, i) => {
        const [meal, glucose, med] = await Promise.all([
          nutritionService.daily(userId, d),
          glucoseService.daily(userId, d),
          medicationService.today(userId, d),
        ]);
        return {
          date: d,
          mealCount: meal.mealCount,
          glucoseCount: glucose.count,
          activityMinutes: act.days[i]?.durationMinutes ?? null,
          medication: { scheduled: med.scheduled, taken: med.taken, skipped: med.skipped, unknown: med.unknown },
        };
      }),
    );
    const summary = summarizeWeek(days);
    const goals = await goalsService.list(userId, { status: "active", limit: 20 });
    const computedAt = new Date();
    const body = {
      weekStart: act.startDate,
      weekEnd: shiftActivityDate(act.startDate, 6),
      timezone: act.timezone,
      ...summary,
      goals: goals.items.map((g: any) => ({
        id: g.id,
        title: g.title,
        goalType: g.goalType,
        target: g.targetValue,
        progress: g.progress,
      })),
      freshness: "CURRENT" as const,
      computationVersion: COMPUTATION_VERSION,
      computedAt: computedAt.toISOString(),
    };
    // Proyeksi turunan: boleh dibuang dan dibuat ulang kapan saja dari tabel sumber.
    const key = { userId, kind: "weekly", periodStart: new Date(act.startDate + "T00:00:00Z"), computationVersion: COMPUTATION_VERSION };
    await prisma.summaryProjection.upsert({
      where: { userId_kind_periodStart_computationVersion: key },
      create: { ...key, coverageStatus: summary.coverageStatus, analyticsState: summary.analyticsState, metrics: JSON.parse(JSON.stringify(body)), computedAt },
      update: { coverageStatus: summary.coverageStatus, analyticsState: summary.analyticsState, metrics: JSON.parse(JSON.stringify(body)), computedAt, freshnessStatus: "CURRENT" },
    });
    return body;
  },
};
