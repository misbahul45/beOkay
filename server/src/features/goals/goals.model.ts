export function shiftGoalDate(date: string, days: number) {
  const value = new Date(date + "T00:00:00Z");
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
}
export function goalBounds(date: string, period: string, locale: string, goalStart: string, goalEnd: string | null) {
  const firstDay = new Intl.Locale(locale).getWeekInfo().firstDay;
  const weekday = new Date(date + "T00:00:00Z").getUTCDay() || 7;
  const startDate = period === "weekly" ? shiftGoalDate(date, -((weekday - firstDay + 7) % 7)) : date;
  const endDate = shiftGoalDate(startDate, period === "weekly" ? 7 : 1);
  return { startDate, endDate, sourceStartDate: goalStart > startDate ? goalStart : startDate, sourceEndDate: goalEnd && shiftGoalDate(goalEnd, 1) < endDate ? shiftGoalDate(goalEnd, 1) : endDate };
}
export type GoalSource = { date: string; status?: string; value?: number };
export function summarizeGoal(type: string, target: number, rows: GoalSource[]) {
  const completed = rows.filter(r => !r.status || r.status === "completed");
  const value = rows.length === 0 ? null : ["record_meals", "record_glucose"].includes(type) ? new Set(completed.map(r => r.date)).size : completed.reduce((s, r) => s + (r.value ?? 1), 0);
  return { value, targetValue: target, ratio: value === null ? null : value / target, recordedDays: new Set(rows.map(r => r.date)).size, sourceCount: rows.length, completedCount: completed.length, skippedCount: rows.filter(r => r.status === "skipped").length, unknownCount: rows.filter(r => r.status === "unknown").length, coverageStatus: rows.length ? "RECORDED_ONLY" : "NO_RECORDS", method: ["record_meals", "record_glucose"].includes(type) ? "DISTINCT_RECORDED_LOCAL_DAYS" : type === "activity_minutes" ? "SUM_REPORTED_MINUTES" : type === "manual_checkins" ? "SUM_COMPLETED_CHECKIN_VALUES" : "COUNT_WALKING_SESSIONS" };
}
