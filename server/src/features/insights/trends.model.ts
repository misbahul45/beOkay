/**
 * Tren harian lintas domain — deskriptif dan jujur.
 * - Tidak ada skor kesehatan, "kepatuhan", atau penilaian nilai glukosa baik/buruk.
 * - Hari tanpa catatan = tidak tercatat (null), bukan nol.
 * - Perbandingan hanya antara perilaku pencatatan/aktivitas dirimu sendiri pada dua periode sama panjang,
 *   dan hanya bila kedua periode punya data.
 */
export type Coverage = "COMPLETE" | "PARTIAL" | "UNKNOWN";

export type DayInput = {
  date: string;
  glucose: number[];
  activityMinutes: number | null;
  mealCount: number;
  carbs: { value: number | null; coverage: Coverage } | null;
  medTaken: number;
  medSkipped: number;
};

const round1 = (n: number) => Math.round(n * 10) / 10;

export function dayRecorded(d: DayInput) {
  return d.glucose.length > 0 || (d.activityMinutes ?? 0) > 0 || d.mealCount > 0 || d.medTaken + d.medSkipped > 0;
}

function streaks(days: DayInput[]) {
  let best = 0;
  let run = 0;
  for (const d of days) {
    run = dayRecorded(d) ? run + 1 : 0;
    best = Math.max(best, run);
  }
  // Hari ini yang belum dicatat tidak memutus rangkaian: hitung mundur dari kemarin.
  let end = days.length - 1;
  if (end >= 0 && !dayRecorded(days[end]!)) end -= 1;
  let current = 0;
  for (let i = end; i >= 0 && dayRecorded(days[i]!); i--) current += 1;
  return { current, best };
}

export type TrendNote =
  | { code: "STREAK"; days: number }
  | { code: "ACTIVITY_MORE"; current: number; previous: number }
  | { code: "ACTIVITY_PERSONAL_BEST_DAY"; date: string; minutes: number }
  | { code: "MORE_DAYS_RECORDED"; current: number; previous: number };

/** `all` = 2N hari berurutan naik: N hari pertama = periode sebelumnya, N terakhir = periode ini. */
export function buildTrends(all: DayInput[]) {
  const n = all.length / 2;
  if (!Number.isInteger(n) || n < 1) throw new Error("buildTrends needs an even, non-empty list of days");
  const prev = all.slice(0, n);
  const cur = all.slice(n);

  const series = cur.map((d) => {
    const g = d.glucose;
    return {
      date: d.date,
      recorded: dayRecorded(d),
      glucose: g.length ? { count: g.length, min: Math.min(...g), max: Math.max(...g) } : null,
      activityMinutes: d.activityMinutes !== null && d.activityMinutes > 0 ? d.activityMinutes : null,
      meals: { count: d.mealCount, carbs: d.carbs },
      medication: { taken: d.medTaken, skipped: d.medSkipped },
    };
  });

  const sumActivity = (ds: DayInput[]) => ds.reduce((s, d) => s + (d.activityMinutes ?? 0), 0);
  const activeDays = (ds: DayInput[]) => ds.filter((d) => (d.activityMinutes ?? 0) > 0).length;
  const recordedDays = (ds: DayInput[]) => ds.filter(dayRecorded).length;
  const readings = (ds: DayInput[]) => ds.reduce((s, d) => s + d.glucose.length, 0);

  const curRecorded = recordedDays(cur);
  const prevRecorded = recordedDays(prev);
  const curActivity = activeDays(cur) > 0 ? sumActivity(cur) : null;
  const prevActivity = activeDays(prev) > 0 ? sumActivity(prev) : null;
  const bestDay = cur.reduce<{ date: string; minutes: number } | null>(
    (b, d) => ((d.activityMinutes ?? 0) > (b?.minutes ?? 0) ? { date: d.date, minutes: d.activityMinutes! } : b),
    null,
  );
  const allGlucose = cur.flatMap((d) => d.glucose);
  const s = streaks(cur);

  // Catatan kemajuan: hanya fakta yang membaik pada perilaku sendiri dan hanya bila pembanding ada.
  const notes: TrendNote[] = [];
  if (s.current >= 2) notes.push({ code: "STREAK", days: s.current });
  if (curActivity !== null && prevActivity !== null && curActivity > prevActivity) notes.push({ code: "ACTIVITY_MORE", current: curActivity, previous: prevActivity });
  if (bestDay && prev.every((d) => (d.activityMinutes ?? 0) < bestDay.minutes) && prevActivity !== null) notes.push({ code: "ACTIVITY_PERSONAL_BEST_DAY", date: bestDay.date, minutes: bestDay.minutes });
  if (prevRecorded > 0 && curRecorded > prevRecorded) notes.push({ code: "MORE_DAYS_RECORDED", current: curRecorded, previous: prevRecorded });

  return {
    days: n,
    startDate: cur[0]!.date,
    endDate: cur[n - 1]!.date,
    analyticsState: curRecorded === 0 ? ("INSUFFICIENT_DATA" as const) : ("READY" as const),
    series,
    /** Aktivitas harian periode pembanding (untuk batang hantu). */
    previous: prev.map((d) => ({ date: d.date, activityMinutes: d.activityMinutes !== null && d.activityMinutes > 0 ? d.activityMinutes : null })),
    consistency: { recordedDays: curRecorded, totalDays: n, previousRecordedDays: prevRecorded, currentStreak: s.current, bestStreak: s.best },
    activity: {
      totalMinutes: curActivity,
      previousTotalMinutes: prevActivity,
      activeDays: activeDays(cur),
      previousActiveDays: activeDays(prev),
      bestDay,
    },
    glucose: {
      readings: readings(cur),
      previousReadings: readings(prev),
      daysWithReadings: cur.filter((d) => d.glucose.length > 0).length,
      min: allGlucose.length ? round1(Math.min(...allGlucose)) : null,
      max: allGlucose.length ? round1(Math.max(...allGlucose)) : null,
    },
    notes,
  };
}
