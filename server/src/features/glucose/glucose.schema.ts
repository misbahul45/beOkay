import { z } from "zod";
import { GLUCOSE_UNITS } from "../preferences/glucose-units.ts";
import { recordTimestamp } from "../../shared/http/record-schema.ts";
import { canonicalGlucose } from "./glucose.model.ts";
export const glucoseFields = z
  .object({
    originalValue: z.number().finite().positive().max(2000).multipleOf(0.0001),
    originalUnit: z.enum(GLUCOSE_UNITS),
    measuredAt: recordTimestamp,
    mealContext: z
      .enum([
        "fasting",
        "before_meal",
        "after_meal",
        "bedtime",
        "other",
        "unknown",
      ])
      .default("unknown"),
    source: z.literal("manual_glucometer").default("manual_glucometer"),
    measurementType: z.literal("capillary_blood").default("capillary_blood"),
    qualityStatus: z
      .enum(["user_reported", "needs_review"])
      .default("user_reported"),
    notes: z.string().trim().max(2000).nullable().default(null),
  })
  .strict();
export const glucoseCreateSchema = glucoseFields
  .extend({ id: z.uuid() })
  .refine((value) => {
    const canonical = canonicalGlucose(value.originalValue, value.originalUnit);
    return canonical.gte(1) && canonical.lte(2000);
  }, "outside technical numeric domain");
export const glucosePatchSchema = glucoseFields
  .partial()
  .extend({
    mealContext: z
      .enum([
        "fasting",
        "before_meal",
        "after_meal",
        "bedtime",
        "other",
        "unknown",
      ])
      .optional(),
    source: z.literal("manual_glucometer").optional(),
    measurementType: z.literal("capillary_blood").optional(),
    qualityStatus: z.enum(["user_reported", "needs_review"]).optional(),
    notes: z.string().trim().max(2000).nullable().optional(),
    expectedVersion: z.number().int().positive(),
    reason: z.string().trim().min(1).max(300),
    archived: z.boolean().optional(),
  })
  .strict()
  .refine(
    (value) =>
      Object.keys(value).some(
        (key) => !["expectedVersion", "reason"].includes(key),
      ),
    "no changes",
  );
export const glucoseQuerySchema = z
  .object({
    date: z.iso.date().optional(),
    cursor: z.uuid().optional(),
    limit: z.coerce.number().int().min(1).max(50).default(20),
    archived: z.enum(["true", "false"]).default("false"),
  })
  .strict();
export type GlucoseInput = z.infer<typeof glucoseCreateSchema>;
export type GlucosePatch = z.infer<typeof glucosePatchSchema>;
