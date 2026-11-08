import { expect, test } from "bun:test";
import {
  calculateNutrition,
  totalNutrition,
} from "../../src/features/nutrition/nutrition.model.ts";
import { mealCreateSchema } from "../../src/features/nutrition/nutrition.schema.ts";

test("nutrients require grams and preserve unknown values", () => {
  expect(
    calculateNutrition(
      { calories: 200, carbohydrates: null, protein: 4, fat: 2, fiber: null },
      150,
    ),
  ).toEqual({
    calories: 300,
    carbohydrates: null,
    protein: 6,
    fat: 3,
    fiber: null,
  });
  expect(calculateNutrition({ calories: 200 }, null).calories).toBeNull();
  const totals = totalNutrition([
    { calories: 300, carbohydrates: null },
    { calories: null, carbohydrates: null },
  ]);
  expect(totals.calories).toEqual({
    value: 300,
    knownItems: 1,
    totalItems: 2,
    coverage: "PARTIAL",
  });
  expect(totals.carbohydrates.value).toBeNull();
});

test("meal validation rejects empty items, impossible dates and unjustified grams", () => {
  const base = {
    id: crypto.randomUUID(),
    category: "lunch",
    consumedAt: new Date(Date.now() - 3600000).toISOString(),
    items: [
      { name: "Unknown food", quantity: 1, unit: "portion", grams: null },
    ],
  };
  expect(mealCreateSchema.safeParse(base).success).toBe(true);
  expect(mealCreateSchema.safeParse({ ...base, items: [] }).success).toBe(
    false,
  );
  expect(
    mealCreateSchema.safeParse({ ...base, consumedAt: "2026-02-30T12:00:00Z" })
      .success,
  ).toBe(false);
  expect(
    mealCreateSchema.safeParse({
      ...base,
      items: [{ name: "Food", quantity: -1, unit: "g" }],
    }).success,
  ).toBe(false);
  expect(
    mealCreateSchema.safeParse({
      ...base,
      items: [{ name: "Food", quantity: 1, unit: "portion", grams: 200 }],
    }).success,
  ).toBe(false);
});
