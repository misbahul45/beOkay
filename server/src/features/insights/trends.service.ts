import { ACTIVITY_COUNTED_QUALITY } from "../activity/activity.model.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { shiftActivityDate } from "../activity/activity.model.ts";
import { consentService } from "../consent/consent.service.ts";
import { nutritionService } from "../nutrition/nutrition.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { buildTrends, type Coverage, type DayInput } from "./trends.model.ts";

export const TRENDS_VERSION = "trends-v1";

export const trendsService = {
  /** `days` hari terakhir (hingga hari ini menurut zona waktu pengguna) + periode pembanding sama panjang. */
  async get(userId: string, days: number) {
    await consentService.requireConsent(userId, "health_data_processing");
    await consentService.requireConsent(userId, "descriptive_summaries");
    const { timezone } = await preferencesService.get(userId);
    const today = localRecordTime(new Date(), timezone).localDate;
    const dates = Array.from({ length: days * 2 }, (_, i) => shiftActivityDate(today, i - (days * 2 - 1)));
    // Batas UTC diperlebar sehari di kedua sisi; pengelompokan akhir memakai tanggal lokal.
    const from = new Date(`${shiftActivityDate(dates[0]!, -1)}T00:00:00Z`);
    const to = new Date(`${shiftActivityDate(today, 2)}T00:00:00Z`);
    const local = (d: Date) => localRecordTime(d, timezone).localDate;

    const [glucose, activity, meals, intakes] = await Promise.all([
      prisma.glucoseObservation.findMany({
        where: { userId, archivedAt: null, qualityStatus: "user_reported", measuredAt: { gte: from, lt: to } },
        select: { measuredAt: true, valueMgDl: true },
      }),
      prisma.activitySession.findMany({
        where: { userId, archivedAt: null, qualityStatus: { in: [...ACTIVITY_COUNTED_QUALITY] }, startedAt: { gte: from, lt: to } },
        select: { startedAt: true, durationMinutes: true },
      }),
      nutritionService.mealsBetween(userId, from, to, timezone),
      prisma.medicationIntake.findMany({
        where: { userId, archivedAt: null, eventAt: { gte: from, lt: to }, status: { in: ["taken", "skipped"] } },
        select: { eventAt: true, status: true },
      }),
    ]);

    const byDate = new Map<string, DayInput>(
      dates.map((date) => [date, { date, glucose: [], activityMinutes: null, mealCount: 0, carbs: null, medTaken: 0, medSkipped: 0 }]),
    );
    for (const g of glucose) byDate.get(local(g.measuredAt))?.glucose.push(g.valueMgDl.toNumber());
    for (const a of activity) {
      const d = byDate.get(local(a.startedAt));
      if (d) d.activityMinutes = (d.activityMinutes ?? 0) + a.durationMinutes;
    }
    const carbItems = new Map<string, (number | null)[]>();
    for (const m of meals as any[]) {
      const d = byDate.get(m.localDate ?? local(new Date(m.consumedAt)));
      if (!d) continue;
      d.mealCount += 1;
      const list = carbItems.get(d.date) ?? [];
      for (const item of m.items) list.push(item.nutrition?.carbohydrates ?? null);
      carbItems.set(d.date, list);
    }
    for (const [date, list] of carbItems) {
      const known = list.filter((v): v is number => v !== null);
      const coverage: Coverage = known.length === 0 ? "UNKNOWN" : known.length === list.length ? "COMPLETE" : "PARTIAL";
      byDate.get(date)!.carbs = { value: known.length ? Math.round(known.reduce((s, v) => s + v, 0) * 10) / 10 : null, coverage };
    }
    for (const i of intakes) {
      const d = byDate.get(local(i.eventAt));
      if (!d) continue;
      if (i.status === "taken") d.medTaken += 1;
      else d.medSkipped += 1;
    }
    return { timezone, ...buildTrends(dates.map((d) => byDate.get(d)!)), computationVersion: TRENDS_VERSION, computedAt: new Date().toISOString() };
  },
};
