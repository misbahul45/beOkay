import { Prisma } from "../../generated/prisma/client.ts";
import { calculateNutrition, nutrients, totalNutrition } from "./nutrition.model.ts";

type Per100g = Partial<Record<(typeof nutrients)[number], number | null>>;

export type PortionInput = {
  name: string;
  per100g: Per100g;
  /** Berat langsung (g) — ditimbang atau diperkirakan pengguna. */
  grams?: number | null;
  gramsBasis?: "weighed" | "user_estimate";
  /** Atau jumlah × ukuran yang gram-nya diketahui untuk makanan ini. */
  quantity?: number;
  measure?: { id: string; label: string; grams: number; basis: "weighed" | "user_estimate" } | null;
};

export type PortionResult = {
  name: string;
  grams: number | null;
  gramsBasis: "weighed" | "user_estimate" | null;
  /** Alasan angka kosong: berat porsi belum diketahui. */
  reason: "PORTION_WEIGHT_UNKNOWN" | null;
  nutrition: Record<(typeof nutrients)[number], number | null>;
};

/** gram = jumlah × gram-per-ukuran (Decimal, 4 desimal). Tanpa berat yang diketahui → null, bukan tebakan. */
export function resolveGrams(input: PortionInput): { grams: number | null; basis: PortionResult["gramsBasis"] } {
  if (input.measure && input.quantity != null)
    return {
      grams: new Prisma.Decimal(input.quantity).mul(input.measure.grams).toDecimalPlaces(4).toNumber(),
      basis: input.measure.basis,
    };
  if (input.grams != null) return { grams: input.grams, basis: input.gramsBasis ?? "user_estimate" };
  return { grams: null, basis: null };
}

export function calculatePortion(input: PortionInput): PortionResult {
  const { grams, basis } = resolveGrams(input);
  return {
    name: input.name,
    grams,
    gramsBasis: grams === null ? null : basis,
    reason: grams === null ? "PORTION_WEIGHT_UNKNOWN" : null,
    nutrition: calculateNutrition(input.per100g, grams),
  };
}

/** Total tiap zat gizi hanya dari item yang nilainya diketahui, dengan cakupan UNKNOWN/PARTIAL/COMPLETE. */
export function calculateMeal(inputs: PortionInput[]) {
  const items = inputs.map((i) => calculatePortion(i));
  return { items, totals: totalNutrition(items.map((i) => i.nutrition)) };
}
