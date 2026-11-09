import { z } from "zod";
import { nutrientSchema } from "./nutrition.schema.ts";

const calcItem = z
  .object({
    name: z.string().trim().min(1).max(120).optional(),
    foodId: z.uuid().optional(),
    per100g: nutrientSchema.optional(),
    grams: z.number().finite().positive().max(1000000).multipleOf(0.0001).optional(),
    gramsBasis: z.enum(["weighed", "user_estimate"]).optional(),
    quantity: z.number().finite().positive().max(10000).multipleOf(0.0001).optional(),
    measureId: z.uuid().optional(),
  })
  .strict()
  .refine((v) => Boolean(v.foodId) !== Boolean(v.per100g), "Isi foodId atau per100g, salah satu.")
  .refine((v) => !v.measureId || (v.foodId && v.quantity !== undefined), "Ukuran porsi butuh foodId dan quantity.")
  .refine((v) => !(v.measureId && v.grams !== undefined), "Pilih berat langsung atau ukuran porsi, bukan keduanya.");

export const calculateSchema = z.object({ items: z.array(calcItem).min(1).max(30) }).strict();
export const measureSchema = z
  .object({
    label: z.string().trim().min(1).max(60),
    grams: z.number().finite().positive().max(1000000).multipleOf(0.0001),
    basis: z.enum(["weighed", "user_estimate"]),
  })
  .strict();
export type CalculateRequest = z.infer<typeof calculateSchema>;
export type MeasureInput = z.infer<typeof measureSchema>;
