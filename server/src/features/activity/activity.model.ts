import { Prisma } from "../../generated/prisma/client.ts";

export function activityEnd(startedAt: string | Date, durationMinutes: number) {
  return new Date(new Date(startedAt).getTime() + durationMinutes * 60000);
}
export function shiftActivityDate(date: string, days: number) {
  const time = new Date(date + "T00:00:00Z");
  time.setUTCDate(time.getUTCDate() + days);
  return time.toISOString().slice(0, 10);
}
export function activityWeek(date: string, locale: string) {
  const firstDay = new Intl.Locale(locale).getWeekInfo().firstDay;
  const weekday = new Date(date + "T00:00:00Z").getUTCDay() || 7;
  const startDate = shiftActivityDate(date, -((weekday - firstDay + 7) % 7));
  return { startDate, endDate: shiftActivityDate(startDate, 7), firstDay };
}
type Report = {
  durationMinutes: number;
  distanceKm: number | Prisma.Decimal | null;
  steps: number | null;
  qualityStatus: string;
};
export function summarizeActivities(rows: Report[]) {
  const eligible = rows.filter((r) => r.qualityStatus === "user_reported");
  function metric(key: "distanceKm" | "steps") {
    const values = eligible.map((r) => r[key]).filter((v) => v !== null);
    return {
      value: values.length
        ? values
            .reduce<Prisma.Decimal>(
              (sum, value) => sum.add(value),
              new Prisma.Decimal(0),
            )
            .toNumber()
        : null,
      knownSessions: values.length,
      totalSessions: eligible.length,
      coverage:
        values.length === 0
          ? "UNKNOWN"
          : values.length === eligible.length
            ? "COMPLETE"
            : "PARTIAL",
    };
  }
  return {
    count: rows.length,
    eligibleCount: eligible.length,
    reviewCount: rows.length - eligible.length,
    durationMinutes: eligible.length
      ? eligible.reduce((sum, r) => sum + r.durationMinutes, 0)
      : null,
    distanceKm: metric("distanceKm"),
    steps: metric("steps"),
  };
}
