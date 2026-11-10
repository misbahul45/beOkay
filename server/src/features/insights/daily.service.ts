import { prisma } from "../../infrastructure/database/prisma.ts";
import { activityService } from "../activity/activity.service.ts";
import { glucoseService } from "../glucose/glucose.service.ts";
import { nutritionService } from "../nutrition/nutrition.service.ts";

export const DAILY_COMPUTATION_VERSION = "daily-cross-domain-v1";

/** Cakupan harian: berapa dari tiga domain (makan, glukosa, aktivitas) yang punya catatan. UNKNOWN bila kosong. */
export function dailyCoverage(counts: { meals: number; glucose: number; activity: number }) {
  const recorded = [counts.meals, counts.glucose, counts.activity].filter((n) => n > 0).length;
  return {
    coverageStatus: recorded === 0 ? "UNKNOWN" : recorded === 3 ? "COMPLETE" : "PARTIAL",
    analyticsState: recorded === 0 ? "INSUFFICIENT_DATA" : "READY",
  } as const;
}

export const dailyService = {
  async get(userId: string, date?: string) {
    const [nutrition, glucose, activity] = await Promise.all([
      nutritionService.daily(userId, date),
      glucoseService.daily(userId, date),
      activityService.daily(userId, date),
    ]);
    const body = { ...nutrition, glucose, activity };
    const { coverageStatus, analyticsState } = dailyCoverage({
      meals: nutrition.mealCount,
      glucose: glucose.count,
      activity: activity.eligibleCount,
    });
    const computedAt = new Date();
    // Proyeksi turunan: dibuang dan dibuat ulang dari tabel sumber kapan saja; respons tetap dihitung baru.
    const key = { userId, kind: "daily", periodStart: new Date(nutrition.date + "T00:00:00Z"), computationVersion: DAILY_COMPUTATION_VERSION };
    const metrics = JSON.parse(JSON.stringify(body));
    await prisma.summaryProjection.upsert({
      where: { userId_kind_periodStart_computationVersion: key },
      create: { ...key, coverageStatus, analyticsState, metrics, computedAt },
      update: { coverageStatus, analyticsState, metrics, computedAt, freshnessStatus: "CURRENT" },
    });
    return body;
  },
};
