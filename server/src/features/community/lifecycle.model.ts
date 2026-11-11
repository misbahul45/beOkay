export const LIFECYCLE_VERSION = "challenge-lifecycle-v1";
export const BUSINESS_TIMEZONE = "Asia/Jakarta";

export type ChallengeStatus = "SCHEDULED" | "OPEN" | "CLOSED";
export type Completion = "COMPLETED" | "PARTICIPATED" | "LEFT";
export type TemplateSpec = { durationDays: number; targetDays: number; cadenceDays: number; anchorDate: string };
export type Period = { startsOn: string; endsOn: string };

export const addDays = (date: string, n: number) => new Date(Date.parse(date + "T00:00:00Z") + n * 86_400_000).toISOString().slice(0, 10);
export const daysBetween = (from: string, to: string) => Math.round((Date.parse(to + "T00:00:00Z") - Date.parse(from + "T00:00:00Z")) / 86_400_000);

export function periodsToEnsure(t: TemplateSpec, today: string): Period[] {
  if (today < t.anchorDate) return [{ startsOn: t.anchorDate, endsOn: addDays(t.anchorDate, t.durationDays - 1) }];
  const k = Math.floor(daysBetween(t.anchorDate, today) / t.cadenceDays);
  const start = addDays(t.anchorDate, k * t.cadenceDays);
  const current = { startsOn: start, endsOn: addDays(start, t.durationDays - 1) };
  const nextStart = addDays(start, t.cadenceDays);
  const next = { startsOn: nextStart, endsOn: addDays(nextStart, t.durationDays - 1) };
  return current.endsOn >= today ? [current, next] : [next];
}

export function statusOn(p: Period, today: string): ChallengeStatus {
  if (today < p.startsOn) return "SCHEDULED";
  if (today > p.endsOn) return "CLOSED";
  return "OPEN";
}

export function completionFor(activeDays: number, targetDays: number, left: boolean): Completion {
  if (left) return "LEFT";
  return activeDays >= targetDays ? "COMPLETED" : "PARTICIPATED";
}

export function participantsLabel(n: number): string {
  if (n < 5) return "kurang dari 5 peserta";
  if (n < 20) return "5–19 peserta";
  return "20+ peserta";
}

export function daysLeft(p: Period, today: string): number | null {
  if (today < p.startsOn || today > p.endsOn) return null;
  return daysBetween(today, p.endsOn) + 1;
}

export function statusLabel(p: Period, today: string): string {
  const s = statusOn(p, today);
  if (s === "SCHEDULED") {
    const d = daysBetween(today, p.startsOn);
    return d === 1 ? "Mulai besok" : `Mulai ${d} hari lagi`;
  }
  if (s === "CLOSED") return "Selesai";
  const left = daysLeft(p, today)!;
  return left === 1 ? "Berjalan · hari terakhir" : `Berjalan · sisa ${left} hari`;
}

export const COMPLETION_LABEL: Record<Completion, string> = { COMPLETED: "Tuntas", PARTICIPATED: "Ikut serta", LEFT: "Keluar" };
