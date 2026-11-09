export type WeekDay = {
  date: string;
  mealCount: number;
  glucoseCount: number;
  activityMinutes: number | null;
  medication: { scheduled: number; taken: number; skipped: number; unknown: number };
};

export type GoalLine = { id: string; title: string; goalType: string; state: string; current: number | null; target: number };

/**
 * Ringkasan mingguan lintas domain — deskriptif saja. Tidak ada korelasi, penilaian klinis,
 * rata-rata glukosa, atau "kepatuhan" obat. Hari tanpa catatan = tidak tercatat, bukan nol.
 */
export function summarizeWeek(days: WeekDay[]) {
  const withData = (pred: (d: WeekDay) => boolean) => days.filter(pred).length;
  const sum = (f: (d: WeekDay) => number) => days.reduce((s, d) => s + f(d), 0);
  const scheduled = sum((d) => d.medication.scheduled);
  const medUnknown = sum((d) => d.medication.unknown);
  const mealDays = withData((d) => d.mealCount > 0);
  const glucoseDays = withData((d) => d.glucoseCount > 0);
  const activityDays = withData((d) => (d.activityMinutes ?? 0) > 0);
  const recordedDays = withData(
    (d) => d.mealCount > 0 || d.glucoseCount > 0 || (d.activityMinutes ?? 0) > 0 || d.medication.taken + d.medication.skipped > 0,
  );
  const known = activityDays > 0 ? sum((d) => d.activityMinutes ?? 0) : null;
  return {
    days,
    recordedDays,
    totalDays: days.length,
    coverageStatus: recordedDays === 0 ? "UNKNOWN" : recordedDays === days.length ? "COMPLETE" : "PARTIAL",
    analyticsState: recordedDays === 0 ? "INSUFFICIENT_DATA" : "READY",
    meals: { total: sum((d) => d.mealCount), daysWithRecords: mealDays },
    glucose: { total: sum((d) => d.glucoseCount), daysWithRecords: glucoseDays },
    activity: { totalMinutes: known, daysWithRecords: activityDays },
    medication: {
      scheduled,
      taken: sum((d) => d.medication.taken),
      skipped: sum((d) => d.medication.skipped),
      unconfirmed: medUnknown,
      coverageStatus: scheduled === 0 ? "NO_SCHEDULE" : medUnknown === 0 ? "COMPLETE" : medUnknown === scheduled ? "UNKNOWN" : "PARTIAL",
    },
  };
}
