export const PROJECTION_VERSION = "daily-facts-v1";

export type SessionRow = { startedAt: Date; durationMinutes: number; source: string };
export type DatedRow = { at: Date };
export type MealRow = { at: Date; category: string };
export type StepsRow = { localDate: string; steps: number; source: string };
export type SleepRow = { startedAt: Date; endedAt: Date; durationMinutes: number; source: string };

export type DayFacts = {
  localDate: string;
  activeMinutes: number;
  activeMinutesManual: number;
  activeMinutesDevice: number;
  sessionCount: number;
  longestSessionMinutes: number | null;
  steps: number | null;
  stepsSources: string[];
  sleepMinutes: number | null;
  mealsLogged: number;
  mealCategories: string[];
  glucoseChecks: number;
  medicationConfirmed: number;
  goalCheckins: number;
  sources: string[];
};

export type DayInputs = {
  sessions: SessionRow[];
  meals: MealRow[];
  glucose: DatedRow[];
  intakes: DatedRow[];
  checkins: DatedRow[];
  steps: StepsRow[];
  sleep: SleepRow[];
};

export function emptyDay(localDate: string): DayFacts {
  return { localDate, activeMinutes: 0, activeMinutesManual: 0, activeMinutesDevice: 0, sessionCount: 0, longestSessionMinutes: null, steps: null, stepsSources: [], sleepMinutes: null, mealsLogged: 0, mealCategories: [], glucoseChecks: 0, medicationConfirmed: 0, goalCheckins: 0, sources: [] };
}

export function aggregateDays(dates: string[], inputs: DayInputs, localDateOf: (d: Date) => string): Map<string, DayFacts> {
  const out = new Map(dates.map((d) => [d, emptyDay(d)]));
  const src = new Map<string, Set<string>>();
  const touch = (date: string, source: string | null) => {
    const f = out.get(date);
    if (!f) return null;
    if (source) (src.get(date) ?? src.set(date, new Set()).get(date)!).add(source);
    return f;
  };
  for (const s of inputs.sessions) {
    const f = touch(localDateOf(s.startedAt), s.source);
    if (!f) continue;
    f.activeMinutes += s.durationMinutes;
    if (s.source === "manual") f.activeMinutesManual += s.durationMinutes;
    else f.activeMinutesDevice += s.durationMinutes;
    f.sessionCount++;
    f.longestSessionMinutes = Math.max(f.longestSessionMinutes ?? 0, s.durationMinutes);
  }
  for (const m of inputs.meals) {
    const f = touch(localDateOf(m.at), "manual");
    if (!f) continue;
    f.mealsLogged++;
    f.mealCategories.push(m.category);
  }
  for (const g of inputs.glucose) {
    const f = touch(localDateOf(g.at), null);
    if (f) f.glucoseChecks++;
  }
  for (const i of inputs.intakes) {
    const f = touch(localDateOf(i.at), null);
    if (f) f.medicationConfirmed++;
  }
  for (const c of inputs.checkins) {
    const f = touch(localDateOf(c.at), null);
    if (f) f.goalCheckins++;
  }
  for (const s of inputs.steps) {
    const f = touch(s.localDate, s.source);
    if (!f) continue;
    f.steps = Math.max(f.steps ?? 0, s.steps);
    if (!f.stepsSources.includes(s.source)) f.stepsSources.push(s.source);
  }
  const sleepByDay = new Map<string, SleepRow[]>();
  for (const s of inputs.sleep) {
    const d = localDateOf(s.endedAt);
    if (!touch(d, s.source)) continue;
    (sleepByDay.get(d) ?? sleepByDay.set(d, []).get(d)!).push(s);
  }
  for (const [d, rows] of sleepByDay) out.get(d)!.sleepMinutes = unionMinutes(rows);
  for (const [d, f] of out) {
    f.sources = [...(src.get(d) ?? [])].sort();
    f.stepsSources.sort();
    f.mealCategories.sort();
  }
  return out;
}

export function isActiveDay(f: Pick<DayFacts, "longestSessionMinutes">, minSessionMinutes: number) {
  return (f.longestSessionMinutes ?? 0) >= minSessionMinutes;
}

export function isRecordedDay(f: Pick<DayFacts, "mealsLogged" | "sessionCount" | "glucoseChecks">) {
  return f.mealsLogged > 0 || f.sessionCount > 0 || f.glucoseChecks > 0;
}

export function datesBetween(from: string, to: string): string[] {
  const out: string[] = [];
  for (let t = Date.parse(from + "T00:00:00Z"); t <= Date.parse(to + "T00:00:00Z"); t += 86_400_000) out.push(new Date(t).toISOString().slice(0, 10));
  return out;
}

export function unionMinutes(rows: { startedAt: Date; endedAt: Date }[]): number {
  const iv = rows.map((r) => [r.startedAt.getTime(), r.endedAt.getTime()] as const).filter(([a, b]) => b > a).sort((x, y) => x[0] - y[0]);
  let total = 0, curStart = -1, curEnd = -1;
  for (const [a, b] of iv) {
    if (a > curEnd) {
      if (curEnd > curStart) total += curEnd - curStart;
      curStart = a;
      curEnd = b;
    } else if (b > curEnd) curEnd = b;
  }
  if (curEnd > curStart) total += curEnd - curStart;
  return Math.round(total / 60_000);
}
