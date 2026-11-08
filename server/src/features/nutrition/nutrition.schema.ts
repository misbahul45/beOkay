import { z } from "zod";

const text = (max: number) =>
  z
    .string()
    .trim()
    .min(1)
    .max(max)
    .regex(/^[^\x00-\x1F\x7F]*$/);
const amount = z
  .number()
  .finite()
  .min(0)
  .max(10000)
  .multipleOf(0.0001)
  .nullable();
export const nutrientSchema = z
  .object({
    calories: amount,
    carbohydrates: amount,
    protein: amount,
    fat: amount,
    fiber: amount,
  })
  .strict();
export const foodSchema = z
  .object({
    name: text(120),
    source: text(160),
    sourceVersion: text(80).nullable().default(null),
    status: z.enum(["user_reported", "estimated"]),
    per100g: nutrientSchema,
  })
  .strict();
const instant = z.iso.datetime({ offset: true }).refine((value) => {
  const parsed = new Date(value);
  return (
    Number.isFinite(parsed.getTime()) &&
    value.slice(0, 10) ===
      new Date(value.slice(0, 10) + "T00:00:00Z").toISOString().slice(0, 10) &&
    parsed.getTime() <= Date.now() + 300000 &&
    parsed.getUTCFullYear() >= 1900
  );
}, "invalid event timestamp");
export const mealItemSchema = z
  .object({
    id: z.uuid().optional(),
    foodId: z.uuid().nullable().optional(),
    name: text(120),
    quantity: z.number().finite().positive().max(10000).multipleOf(0.0001),
    unit: z.enum(["g", "portion", "piece", "ml"]),
    grams: z
      .number()
      .finite()
      .positive()
      .max(1000000)
      .multipleOf(0.0001)
      .nullable()
      .default(null),
    gramsBasis: z.enum(["weighed", "user_estimate"]).nullable().default(null),
  })
  .strict()
  .refine(
    (item) =>
      item.unit === "g" || item.grams === null || item.gramsBasis !== null,
    "grams require provenance",
  )
  .refine(
    (item) =>
      item.unit !== "g" || item.grams === null || item.grams === item.quantity,
    "gram quantity mismatch",
  );
export const mealCreateSchema = z
  .object({
    id: z.uuid(),
    category: z.enum(["breakfast", "lunch", "dinner", "snack"]),
    consumedAt: instant,
    notes: z.string().trim().max(2000).nullable().default(null),
    items: z.array(mealItemSchema).min(1).max(30),
  })
  .strict();
export const mealPatchSchema = mealCreateSchema
  .omit({ id: true })
  .partial()
  .extend({
    expectedVersion: z.number().int().positive(),
    reason: text(300),
    archived: z.boolean().optional(),
  })
  .strict()
  .refine(
    (value) =>
      [
        value.category,
        value.consumedAt,
        value.notes,
        value.items,
        value.archived,
      ].some((v) => v !== undefined),
    "no changes",
  );
export const mealQuerySchema = z
  .object({
    date: z.iso.date().optional(),
    cursor: z.uuid().optional(),
    limit: z.coerce.number().int().min(1).max(30).default(20),
    archived: z.enum(["true", "false"]).default("false"),
  })
  .strict();
export type MealInput = z.infer<typeof mealCreateSchema>;
export type MealPatch = z.infer<typeof mealPatchSchema>;
