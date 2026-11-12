import { prisma } from "../../infrastructure/database/prisma.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { ACTIVITY_COUNTED_QUALITY } from "../activity/activity.model.ts";
import { GLUCOSE_COUNTED_QUALITY } from "../glucose/glucose.model.ts";
import { medicationService } from "../medication/medication.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";

export const COMPANION_SUMMARY_VERSION = "companion-summary-v1";
const DAY = 86_400_000;

export function lastDays(today: string, n: number) {
  const base = Date.parse(today + "T00:00:00Z");
  return Array.from({ length: n }, (_, i) => new Date(base - (n - 1 - i) * DAY).toISOString().slice(0, 10));
}

export async function companionSummary(userId: string, now = new Date()) {
  const { timezone } = await preferencesService.get(userId);
  const today = localRecordTime(now, timezone).localDate;
  const days = lastDays(today, 7);
  const from = new Date(Date.parse(days[0]! + "T00:00:00Z") - DAY);
  const to = new Date(now.getTime() + 60_000);
  const span = { gte: from, lt: to };
  const [meals, glucose, activity, vitals] = await Promise.all([
    prisma.mealLog.findMany({ where: { userId, archivedAt: null, consumedAt: span }, select: { consumedAt: true } }),
    prisma.glucoseObservation.findMany({ where: { userId, archivedAt: null, qualityStatus: { in: [...GLUCOSE_COUNTED_QUALITY] }, measuredAt: span }, select: { measuredAt: true } }),
    prisma.activitySession.findMany({ where: { userId, archivedAt: null, qualityStatus: { in: [...ACTIVITY_COUNTED_QUALITY] }, startedAt: span }, select: { startedAt: true, durationMinutes: true } }),
    prisma.vitalMeasurement.findMany({ where: { userId, archivedAt: null, measuredAt: span }, select: { measuredAt: true } }),
  ]);
  const inWindow = (d: Date) => days.includes(localRecordTime(d, timezone).localDate);
  const recordDays = new Set<string>();
  for (const t of [...meals.map((m) => m.consumedAt), ...glucose.map((g) => g.measuredAt), ...activity.map((a) => a.startedAt), ...vitals.map((v) => v.measuredAt)]) {
    if (inWindow(t)) recordDays.add(localRecordTime(t, timezone).localDate);
  }
  let scheduled = 0;
  let taken = 0;
  const unconfirmed: { localDate: string; localTime: string }[] = [];
  for (const date of days) {
    const occ = await medicationService.today(userId, date);
    for (const o of occ.items) {
      if (new Date(o.scheduledAt) > now) continue;
      scheduled++;
      if (o.status === "taken") {
        taken++;
        recordDays.add(date);
      } else if (o.status === "unknown") unconfirmed.push({ localDate: date, localTime: o.localTime });
    }
  }
  return {
    version: COMPANION_SUMMARY_VERSION,
    period: { start: days[0]!, end: today },
    timezone,
    daysWithRecords: recordDays.size,
    totalDays: 7,
    activityMinutes: activity.filter((a) => inWindow(a.startedAt)).reduce((s, a) => s + a.durationMinutes, 0),
    glucoseChecks: glucose.filter((g) => inWindow(g.measuredAt)).length,
    medication: { scheduled, confirmedTaken: taken, unconfirmed: unconfirmed.slice(-14) },
    notice: "Ringkasan baca-saja dari catatan pengguna. Bukan catatan medis. Pengingat yang belum dikonfirmasi belum tentu terlewat.",
  };
}

export type CompanionSummary = Awaited<ReturnType<typeof companionSummary>>;
