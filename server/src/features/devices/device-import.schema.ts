import { z } from "zod";
import { recordTimestamp } from "../../shared/http/record-schema.ts";

const externalId = z.string().trim().min(1).max(200);
const localDate = z.iso.date().refine((d) => d >= "2000-01-01" && Date.parse(d + "T00:00:00Z") <= Date.now() + 2 * 86_400_000, "invalid date");

export const devicePreferencesSchema = z
  .object({ workouts: z.boolean(), steps: z.boolean(), weight: z.boolean(), glucose: z.boolean(), sleep: z.boolean() })
  .partial()
  .strict()
  .refine((v) => Object.keys(v).length > 0, "no changes");

export const deviceImportSchema = z
  .object({
    source: z.literal("health_connect"),
    steps: z.array(z.object({ localDate, steps: z.number().int().min(0).max(200000) }).strict()).max(62).default([]),
    weights: z.array(z.object({ externalId, measuredAt: recordTimestamp, kg: z.number().finite().min(10).max(500) }).strict()).max(100).default([]),
    glucose: z
      .array(
        z
          .object({
            externalId,
            measuredAt: recordTimestamp,
            value: z.number().finite().positive().max(2000),
            unit: z.enum(["mg/dL", "mmol/L"]),
            specimen: z.enum(["capillary_blood", "interstitial_fluid", "unknown"]).default("unknown"),
            mealContext: z.enum(["fasting", "before_meal", "after_meal", "bedtime", "other", "unknown"]).default("unknown"),
          })
          .strict(),
      )
      .max(300)
      .default([]),
    sleep: z.array(z.object({ externalId, startedAt: recordTimestamp, endedAt: recordTimestamp }).strict()).max(62).default([]),
  })
  .strict()
  .refine((v) => v.steps.length + v.weights.length + v.glucose.length + v.sleep.length > 0, "empty import");

export type DevicePreferencesInput = z.infer<typeof devicePreferencesSchema>;
export type DeviceImportInput = z.infer<typeof deviceImportSchema>;
