import { unionMinutes } from "../projections/daily-facts.model.ts";

export const QUALITY_VERSION = "device-quality-v1";

export const SIGNALS = ["steps", "sleep", "workouts"] as const;
export type Signal = (typeof SIGNALS)[number];

export type QualityStatus = "OK" | "PARTIAL" | "NO_DATA" | "NOT_CONNECTED" | "STALE" | "CONFLICT" | "IMPLAUSIBLE";
export type QualityFlag = "LATE_SYNC" | "MULTIPLE_ORIGINS" | "OVERLAPPING_SESSIONS" | "NEEDS_REVIEW_SESSIONS" | "DAY_IN_PROGRESS" | "VALUE_OUT_OF_RANGE";
export type ActivityInference = "OBSERVED" | "UNKNOWN";

export const STALE_AFTER_HOURS = 48;
export const LATE_SYNC_HOURS = 48;
export const MAX_PLAUSIBLE_STEPS = 60_000;
export const MAX_PLAUSIBLE_SLEEP_MINUTES = 16 * 60;

export type StepsInput = { localDate: string; steps: number; dataOrigin: string | null; syncedAt: Date };
export type SleepInput = { startedAt: Date; endedAt: Date; dataOrigin: string | null; createdAt: Date; localDate: string };
export type WorkoutInput = { startedAt: Date; durationMinutes: number; dataOrigin: string | null; receivedAt: Date; qualityStatus: string; localDate: string };

export type DayQuality = {
  signal: Signal;
  localDate: string;
  status: QualityStatus;
  flags: QualityFlag[];
  value: number | null;
  origins: string[];
  inference: ActivityInference;
};

export type QualityContext = { today: string; now: Date; connected: boolean; lastSyncAt: Date | null };

const hoursBetween = (a: Date, b: Date) => Math.abs(a.getTime() - b.getTime()) / 3_600_000;
const endOfDay = (d: string) => new Date(Date.parse(d + "T00:00:00Z") + 86_400_000);
const uniq = (xs: (string | null)[]) => [...new Set(xs.map((x) => x ?? "unknown"))].sort();

function base(signal: Signal, localDate: string, ctx: QualityContext, hasData: boolean): { status: QualityStatus; flags: QualityFlag[] } | null {
  if (!ctx.connected && !hasData) return { status: "NOT_CONNECTED", flags: [] };
  if (!hasData) {
    const stale = ctx.lastSyncAt === null || hoursBetween(ctx.now, ctx.lastSyncAt) > STALE_AFTER_HOURS;
    return { status: stale && localDate >= addDays(ctx.today, -2) ? "STALE" : "NO_DATA", flags: [] };
  }
  return null;
}

export function addDays(d: string, n: number) {
  return new Date(Date.parse(d + "T00:00:00Z") + n * 86_400_000).toISOString().slice(0, 10);
}

export function assessSteps(localDate: string, rows: StepsInput[], ctx: QualityContext): DayQuality {
  const empty = base("steps", localDate, ctx, rows.length > 0);
  if (empty) return { signal: "steps", localDate, ...empty, value: null, origins: [], inference: "UNKNOWN" };
  const flags: QualityFlag[] = [];
  const value = Math.max(...rows.map((r) => r.steps));
  const origins = uniq(rows.map((r) => r.dataOrigin));
  if (origins.length > 1) flags.push("MULTIPLE_ORIGINS");
  if (rows.some((r) => r.syncedAt.getTime() - endOfDay(localDate).getTime() > LATE_SYNC_HOURS * 3_600_000)) flags.push("LATE_SYNC");
  let status: QualityStatus = "OK";
  if (value > MAX_PLAUSIBLE_STEPS) {
    status = "IMPLAUSIBLE";
    flags.push("VALUE_OUT_OF_RANGE");
  } else if (localDate === ctx.today) {
    status = "PARTIAL";
    flags.push("DAY_IN_PROGRESS");
  }
  return { signal: "steps", localDate, status, flags, value, origins, inference: status === "OK" || status === "PARTIAL" ? "OBSERVED" : "UNKNOWN" };
}

export function assessSleep(localDate: string, rows: SleepInput[], ctx: QualityContext): DayQuality {
  const empty = base("sleep", localDate, ctx, rows.length > 0);
  if (empty) return { signal: "sleep", localDate, ...empty, value: null, origins: [], inference: "UNKNOWN" };
  const flags: QualityFlag[] = [];
  const origins = uniq(rows.map((r) => r.dataOrigin));
  const sorted = [...rows].sort((a, b) => a.startedAt.getTime() - b.startedAt.getTime());
  let overlap = false;
  for (let i = 1; i < sorted.length; i++) if (sorted[i]!.startedAt < sorted[i - 1]!.endedAt) overlap = true;
  if (origins.length > 1) flags.push("MULTIPLE_ORIGINS");
  if (overlap) flags.push("OVERLAPPING_SESSIONS");
  if (rows.some((r) => hoursBetween(r.createdAt, r.endedAt) > LATE_SYNC_HOURS)) flags.push("LATE_SYNC");
  const value = unionMinutes(rows);
  let status: QualityStatus = "OK";
  if (value > MAX_PLAUSIBLE_SLEEP_MINUTES) {
    status = "IMPLAUSIBLE";
    flags.push("VALUE_OUT_OF_RANGE");
  } else if (overlap && origins.length > 1) status = "CONFLICT";
  return { signal: "sleep", localDate, status, flags, value, origins, inference: status === "OK" || status === "CONFLICT" ? "OBSERVED" : "UNKNOWN" };
}

export function assessWorkouts(localDate: string, rows: WorkoutInput[], ctx: QualityContext): DayQuality {
  const empty = base("workouts", localDate, ctx, rows.length > 0);
  if (empty) return { signal: "workouts", localDate, ...empty, value: null, origins: [], inference: "UNKNOWN" };
  const flags: QualityFlag[] = [];
  const counted = rows.filter((r) => r.qualityStatus === "device_reported");
  if (counted.length < rows.length) flags.push("NEEDS_REVIEW_SESSIONS");
  const origins = uniq(rows.map((r) => r.dataOrigin));
  if (origins.length > 1) flags.push("MULTIPLE_ORIGINS");
  if (rows.some((r) => hoursBetween(r.receivedAt, r.startedAt) > LATE_SYNC_HOURS)) flags.push("LATE_SYNC");
  const value = counted.reduce((s, r) => s + r.durationMinutes, 0);
  const status: QualityStatus = counted.length < rows.length ? "CONFLICT" : localDate === ctx.today ? "PARTIAL" : "OK";
  return { signal: "workouts", localDate, status, flags, value, origins, inference: counted.length ? "OBSERVED" : "UNKNOWN" };
}

export type SignalSummary = { signal: Signal; days: number; observedDays: number; coverage: number; statusCounts: Partial<Record<QualityStatus, number>>; reliable: boolean };

export const RELIABLE_COVERAGE = 0.6;

export function summarize(signal: Signal, days: DayQuality[]): SignalSummary {
  const statusCounts: Partial<Record<QualityStatus, number>> = {};
  for (const d of days) statusCounts[d.status] = (statusCounts[d.status] ?? 0) + 1;
  const observedDays = days.filter((d) => d.status === "OK" || d.status === "PARTIAL").length;
  const coverage = days.length ? Math.round((observedDays / days.length) * 100) / 100 : 0;
  const bad = (statusCounts.CONFLICT ?? 0) + (statusCounts.IMPLAUSIBLE ?? 0);
  return { signal, days: days.length, observedDays, coverage, statusCounts, reliable: coverage >= RELIABLE_COVERAGE && bad === 0 };
}
