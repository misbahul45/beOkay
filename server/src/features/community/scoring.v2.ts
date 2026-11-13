import type { DayFacts } from "../projections/daily-facts.model.ts";
import { MIN_ACTIVITY_MINUTES } from "./scoring.model.ts";

export const SCORING_V2_VERSION = "score-v2";
export const V2_WEIGHTS = { deviceObservedDay: 1, manualOnlyDay: 0.8, selfProgressBonus: 0.5, dailyCap: 1 } as const;
export const MIN_PEER_GROUP = 5;
export const BREAK_DAYS = 7;
export const FORBIDDEN_RANKING_INPUTS = ["glucose", "hba1c", "weight", "calories", "diagnosis", "medication", "intensity", "heartRate"] as const;

type Day = Pick<DayFacts, "localDate" | "longestSessionMinutes" | "activeMinutesDevice" | "activeMinutesManual" | "goalCheckins">;

export const isActive = (d: Day) => (d.longestSessionMinutes ?? 0) >= MIN_ACTIVITY_MINUTES || d.goalCheckins > 0;

export function dayPoints(d: Day): number {
  if (!isActive(d)) return 0;
  const device = d.activeMinutesDevice >= MIN_ACTIVITY_MINUTES;
  return Math.min(V2_WEIGHTS.dailyCap, device ? V2_WEIGHTS.deviceObservedDay : V2_WEIGHTS.manualOnlyDay);
}

export function weekScore(week: Day[], baselineActiveDays: number | null) {
  const activeDays = week.filter(isActive).length;
  const effort = week.reduce((s, d) => s + dayPoints(d), 0);
  const progress = baselineActiveDays !== null && activeDays > baselineActiveDays ? V2_WEIGHTS.selfProgressBonus : 0;
  return { version: SCORING_V2_VERSION, activeDays, deviceDays: week.filter((d) => isActive(d) && d.activeMinutesDevice >= MIN_ACTIVITY_MINUTES).length, effort: Math.round(effort * 100) / 100, selfProgressBonus: progress, total: Math.round((effort + progress) * 100) / 100 };
}

export function baselineActiveDaysPerWeek(prior: Day[]): number | null {
  if (prior.length < 14) return null;
  const weeks = Math.floor(prior.length / 7);
  const recent = prior.slice(-weeks * 7);
  return Math.round((recent.filter(isActive).length / weeks) * 10) / 10;
}

export function personalBest(days: Day[]) {
  let best7 = 0, streak = 0, longest = 0;
  const sorted = [...days].sort((a, b) => a.localDate.localeCompare(b.localDate));
  for (let i = 0; i < sorted.length; i++) {
    if (i >= 6) best7 = Math.max(best7, sorted.slice(i - 6, i + 1).filter(isActive).length);
    streak = isActive(sorted[i]!) ? streak + 1 : 0;
    longest = Math.max(longest, streak);
  }
  if (sorted.length < 7) best7 = sorted.filter(isActive).length;
  return { best7DayActive: best7, longestStreak: longest };
}

export function returnAfterBreak(days: Day[], today: string): { returned: boolean; gapDays: number | null } {
  const sorted = [...days].sort((a, b) => a.localDate.localeCompare(b.localDate));
  const todayFact = sorted.find((d) => d.localDate === today);
  if (!todayFact || !isActive(todayFact)) return { returned: false, gapDays: null };
  const before = sorted.filter((d) => d.localDate < today && isActive(d)).map((d) => d.localDate);
  const last = before.at(-1);
  if (!last) return { returned: false, gapDays: null };
  const gap = Math.round((Date.parse(today + "T00:00:00Z") - Date.parse(last + "T00:00:00Z")) / 86_400_000) - 1;
  return { returned: gap >= BREAK_DAYS, gapDays: gap };
}

export const PEER_BANDS = [
  { band: "0-1", lo: 0, hi: 1.5 },
  { band: "2-3", lo: 1.5, hi: 3.5 },
  { band: "4-5", lo: 3.5, hi: 5.5 },
  { band: "6-7", lo: 5.5, hi: 7.1 },
] as const;
export const bandOf = (activeDaysPerWeek: number | null) => (activeDaysPerWeek === null ? null : PEER_BANDS.find((b) => activeDaysPerWeek >= b.lo && activeDaysPerWeek < b.hi)!.band);

export function peerComparison(mine: number, peers: number[]): { comparable: boolean; groupSize: number; half: "UPPER" | "LOWER" | null } {
  if (peers.length + 1 < MIN_PEER_GROUP) return { comparable: false, groupSize: peers.length + 1, half: null };
  const below = peers.filter((p) => p < mine).length;
  return { comparable: true, groupSize: peers.length + 1, half: below >= peers.length / 2 ? "UPPER" : "LOWER" };
}
