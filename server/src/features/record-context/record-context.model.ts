import { median } from "../usage/usage.model.ts";

export const CONTEXT_VERSION = "record-context-v1";
export const WINDOW_DAYS = 14;
export const MIN_COMPARISON = 3;
export const SIMILAR_FRACTION = 0.05;

export type Comparison = "LOWER" | "SIMILAR" | "HIGHER";

export const CONTEXT_LABEL: Record<string, string> = {
  fasting: "puasa",
  before_meal: "sebelum makan",
  after_meal: "setelah makan",
  bedtime: "sebelum tidur",
};

export const MEAL_LABEL: Record<string, string> = { breakfast: "sarapan", lunch: "makan siang", dinner: "makan malam", snack: "camilan" };

export function compare(value: number, values: number[]): { median: number; n: number; comparison: Comparison } | null {
  if (values.length < MIN_COMPARISON) return null;
  const m = median(values)!;
  const diff = value - m;
  const comparison: Comparison = m > 0 && Math.abs(diff) / m < SIMILAR_FRACTION ? "SIMILAR" : diff < 0 ? "LOWER" : "HIGHER";
  return { median: m, n: values.length, comparison };
}

export function comparisonPhrase(c: Comparison) {
  return c === "LOWER" ? "Lebih rendah dari" : c === "HIGHER" ? "Lebih tinggi dari" : "Mirip dengan";
}

export function glucoseLine(c: { median: number; n: number; comparison: Comparison }, context: string | null, unit: string) {
  const label = context ? `median ${CONTEXT_LABEL[context]} ${WINDOW_DAYS} harimu` : `median ${WINDOW_DAYS} harimu`;
  return `${comparisonPhrase(c.comparison)} ${label}: ${fmt(c.median)} ${unit} dari ${c.n} catatan.`;
}

export function carbLine(c: { median: number; n: number; comparison: Comparison }, category: string) {
  return `Karbohidrat ${comparisonPhrase(c.comparison).toLowerCase()} median ${MEAL_LABEL[category] ?? "makan"} ${WINDOW_DAYS} harimu: ${fmt(c.median)} g dari ${c.n} catatan.`;
}

export function insufficientLine(n: number) {
  return `Belum cukup catatan pembanding (${n} dari ${MIN_COMPARISON}). Perbandingan muncul setelah ada ${MIN_COMPARISON} catatan serupa dalam ${WINDOW_DAYS} hari.`;
}

const fmt = (v: number) => (Number.isInteger(v) ? String(v) : v.toFixed(1).replace(".", ","));

export type Reading = { id: string; at: Date; value: number; mealContext: string };

export function pairAround(mealAt: Date, readings: Reading[]) {
  const t = mealAt.getTime();
  const min = 60_000;
  const before = readings
    .filter((r) => r.at.getTime() >= t - 90 * min && r.at.getTime() <= t + 10 * min)
    .sort((a, b) => Math.abs(a.at.getTime() - t) - Math.abs(b.at.getTime() - t))[0] ?? null;
  const target = t + 120 * min;
  const after = readings
    .filter((r) => r.at.getTime() >= t + 60 * min && r.at.getTime() <= t + 180 * min && r.id !== before?.id)
    .sort((a, b) => Math.abs(a.at.getTime() - target) - Math.abs(b.at.getTime() - target))[0] ?? null;
  return { before, after };
}
