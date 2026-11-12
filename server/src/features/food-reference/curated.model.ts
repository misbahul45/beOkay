import type { CuratedDish } from "../../content/food/curated-dishes.ts";

export type Per100 = { water: number | null; calories: number | null; protein: number | null; fat: number | null; carbohydrates: number | null; fiber: number | null };
export type IngredientRef = Per100 & { id: string; code: string; name: string };
const NUTRIENTS = ["calories", "protein", "fat", "carbohydrates", "fiber"] as const;
const r1 = (v: number) => Math.round(v * 10) / 10;

export function totalGrams(dish: CuratedDish) {
  return dish.ingredients.reduce((s, [, g]) => s + g, 0) + (dish.addedWaterG ?? 0);
}

export function composeDish(dish: CuratedDish, refs: Map<string, IngredientRef>): { ok: true; per100g: Per100; missing: [] } | { ok: false; missing: string[] } {
  const missing = dish.ingredients.map(([c]) => c).filter((c) => !refs.has(c));
  if (missing.length) return { ok: false, missing };
  const total = totalGrams(dish);
  const sum = (k: keyof Per100) => {
    let acc = 0;
    for (const [code, grams] of dish.ingredients) {
      const v = refs.get(code)![k];
      if (v === null) return null;
      acc += (v * grams) / 100;
    }
    return acc;
  };
  const water = (() => {
    const w = sum("water");
    return w === null ? null : r1(((w + (dish.addedWaterG ?? 0)) / total) * 100);
  })();
  const per100g = { water } as Per100;
  for (const k of NUTRIENTS) {
    const v = sum(k);
    per100g[k] = v === null ? null : r1((v / total) * 100);
  }
  return { ok: true, per100g, missing: [] };
}

export function recipeText(dish: CuratedDish, refs: Map<string, IngredientRef>) {
  const parts = dish.ingredients.map(([c, g]) => `${refs.get(c)?.name ?? c} (${c}) ${g} g`);
  if (dish.addedWaterG) parts.push(`air ${dish.addedWaterG} g`);
  return parts.join("; ");
}

export function methodText(dish: CuratedDish) {
  const base = `Jumlah gizi bahan TKPI 2017 menurut resep standar beOkay dibagi berat total hidangan ${totalGrams(dish)} g${dish.addedWaterG ? ` (termasuk air/kuah ${dish.addedWaterG} g)` : ""}. Tanpa faktor retensi zat gizi dan susut masak. Disusun pengembang, belum ditinjau ahli gizi.`;
  return dish.note ? `${base} ${dish.note}` : base;
}
