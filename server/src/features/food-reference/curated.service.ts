import { prisma } from "../../infrastructure/database/prisma.ts";
import { CURATED_DISHES, CURATED_SOURCE, CURATED_VERSION, type CuratedDish } from "../../content/food/curated-dishes.ts";
import { normalizeTerm } from "../food-preferences/food-preferences.model.ts";
import { composeDish, methodText, recipeText, type IngredientRef } from "./curated.model.ts";

export const CURATED_FLAGS = ["needs_dietitian_review"];

export async function applyCuratedDishes(dishes: CuratedDish[] = CURATED_DISHES) {
  const codes = [...new Set(dishes.flatMap((d) => d.ingredients.map(([c]) => c)))];
  const rows = await prisma.foodReference.findMany({ where: { code: { in: codes }, status: "verified_auto" } });
  const refs = new Map<string, IngredientRef>(
    rows.map((r) => [r.code, { id: r.id, code: r.code, name: r.name, water: r.water?.toNumber() ?? null, calories: r.calories?.toNumber() ?? null, protein: r.protein?.toNumber() ?? null, fat: r.fat?.toNumber() ?? null, carbohydrates: r.carbohydrates?.toNumber() ?? null, fiber: r.fiber?.toNumber() ?? null }]),
  );
  const applied: string[] = [];
  const skipped: { code: string; missing: string[] }[] = [];
  for (const dish of dishes) {
    const c = composeDish(dish, refs);
    if (!c.ok) {
      skipped.push({ code: dish.code, missing: c.missing });
      continue;
    }
    const data = {
      name: dish.name,
      nameNormalized: normalizeTerm(dish.name),
      source: CURATED_SOURCE,
      sourceVersion: CURATED_VERSION,
      sourceRef: `Resep: ${recipeText(dish, refs)}`,
      page: null,
      chapter: null,
      status: "curated",
      flags: CURATED_FLAGS,
      ...c.per100g,
      ash: null,
      servingMinG: dish.serving.min,
      servingTypicalG: dish.serving.typical,
      servingMaxG: dish.serving.max,
      method: methodText(dish),
    };
    await prisma.$transaction(async (tx) => {
      const food = await tx.foodReference.upsert({ where: { code: dish.code }, create: { code: dish.code, ...data }, update: data });
      await tx.foodRecipeItem.deleteMany({ where: { foodId: food.id } });
      await tx.foodRecipeItem.createMany({ data: dish.ingredients.map(([code, grams], position) => ({ foodId: food.id, ingredientId: refs.get(code)!.id, grams, position })) });
    });
    applied.push(dish.code);
  }
  return { applied, skipped };
}
