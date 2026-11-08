import { z } from "zod";
import { recordTimestamp } from "../../shared/http/record-schema.ts";
import { activityEnd } from "./activity.model.ts";
export const activityFields = z
  .object({
    activityType: z.enum([
      "walking",
      "cycling",
      "running",
      "strength",
      "other",
    ]),
    startedAt: recordTimestamp,
    durationMinutes: z.number().int().min(1).max(1440),
    distanceKm: z
      .number()
      .finite()
      .min(0)
      .max(1000)
      .multipleOf(0.001)
      .nullable()
      .optional(),
    steps: z.number().int().min(0).max(1000000).nullable().optional(),
    reportedIntensity: z
      .enum(["unknown", "light", "moderate", "vigorous"])
      .optional(),
    source: z.literal("manual").optional(),
    qualityStatus: z.enum(["user_reported", "needs_review"]).optional(),
    notes: z.string().trim().max(2000).nullable().optional(),
  })
  .strict();
export const activityCreateSchema = activityFields
  .extend({
    id: z.uuid(),
    distanceKm: activityFields.shape.distanceKm.default(null),
    steps: activityFields.shape.steps.default(null),
    reportedIntensity:
      activityFields.shape.reportedIntensity.default("unknown"),
    source: activityFields.shape.source.default("manual"),
    qualityStatus: activityFields.shape.qualityStatus.default("user_reported"),
    notes: activityFields.shape.notes.default(null),
  })
  .refine(
    (v) =>
      activityEnd(v.startedAt, v.durationMinutes).getTime() <=
      Date.now() + 300000,
    "activity must have ended",
  );
export const activityPatchSchema = activityFields
  .partial()
  .extend({
    expectedVersion: z.number().int().positive(),
    reason: z.string().trim().min(1).max(300),
    archived: z.boolean().optional(),
  })
  .strict()
  .refine(
    (v) =>
      Object.keys(v).some((k) => !["expectedVersion", "reason"].includes(k)),
    "no changes",
  );
export const activityQuerySchema = z
  .object({
    date: z.iso.date().optional(),
    cursor: z.uuid().optional(),
    limit: z.coerce.number().int().min(1).max(50).default(20),
    archived: z.enum(["true", "false"]).default("false"),
  })
  .strict();
export type ActivityInput = z.infer<typeof activityCreateSchema>;
export type ActivityPatch = z.infer<typeof activityPatchSchema>;
