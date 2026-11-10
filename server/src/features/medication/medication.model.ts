/** Pure schedule helpers. A recurring local schedule is never frozen to one UTC hour. */
export function isoWeekday(date: string) {
  return new Date(date + "T00:00:00Z").getUTCDay() || 7;
}
function offsetMs(instant: number, timezone: string) {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone: timezone, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit" }).formatToParts(new Date(instant));
  const p = (t: string) => Number(parts.find((x) => x.type === t)!.value);
  return Date.UTC(p("year"), p("month") - 1, p("day"), p("hour"), p("minute"), p("second")) - Math.floor(instant / 1000) * 1000;
}
/** Local wall time in an IANA zone -> UTC instant. Nonexistent (DST gap) times move forward; ambiguous times take the first occurrence. */
export function zonedToUtc(date: string, localTime: string, timezone: string) {
  const [y, m, d] = date.split("-").map(Number);
  const [h, mi] = localTime.split(":").map(Number);
  const wall = Date.UTC(y!, m! - 1, d, h, mi);
  const first = wall - offsetMs(wall, timezone);
  const second = wall - offsetMs(first, timezone);
  // Bila hasil kedua tidak kembali ke jam dinding yang diminta, jam itu jatuh di celah DST: pakai tebakan pertama (maju).
  return new Date(second + offsetMs(second, timezone) === wall ? second : first);
}
export function validTimezone(timezone: string) {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: timezone });
    return true;
  } catch {
    return false;
  }
}
export type Occurrence = { scheduleId: string; regimenId: string; scheduledAt: Date; localTime: string };
type ScheduleLike = { id: string; regimenId: string; localTime: string; timezone: string; daysOfWeek: number[]; enabled: boolean; effectiveFrom: Date };
/** Scheduled occurrences for one local calendar date. A schedule is not evidence that a dose was taken. */
export function occurrencesFor(date: string, schedules: ScheduleLike[]): Occurrence[] {
  const weekday = isoWeekday(date);
  return schedules
    .filter((s) => s.enabled && s.daysOfWeek.includes(weekday) && s.effectiveFrom.toISOString().slice(0, 10) <= date)
    .map((s) => ({ scheduleId: s.id, regimenId: s.regimenId, scheduledAt: zonedToUtc(date, s.localTime, s.timezone), localTime: s.localTime }))
    .sort((a, b) => a.scheduledAt.getTime() - b.scheduledAt.getTime());
}
export type IntakeStatus = "taken" | "skipped" | "unknown";
export function summarizeOccurrences(rows: { status: IntakeStatus }[]) {
  const count = (s: IntakeStatus) => rows.filter((r) => r.status === s).length;
  return { scheduled: rows.length, taken: count("taken"), skipped: count("skipped"), unknown: count("unknown"), coverageStatus: rows.length === 0 ? "NO_SCHEDULE" : count("unknown") === 0 ? "COMPLETE" : count("unknown") === rows.length ? "UNKNOWN" : "PARTIAL" };
}
