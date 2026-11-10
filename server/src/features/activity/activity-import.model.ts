import { z } from "zod";
import { recordTimestamp } from "../../shared/http/record-schema.ts";

export const IMPORT_SOURCES = ["health_connect", "apple_health"] as const;

export const importSessionSchema = z
  .object({
    externalId: z.string().trim().min(1).max(200),
    activityType: z.enum(["walking", "cycling", "running", "strength", "other"]),
    startedAt: recordTimestamp,
    durationMinutes: z.number().int().min(1).max(1440),
    distanceKm: z.number().finite().min(0).max(1000).multipleOf(0.001).nullable().optional(),
    steps: z.number().int().min(0).max(1_000_000).nullable().optional(),
  })
  .strict();

export const importRequestSchema = z
  .object({ source: z.enum(IMPORT_SOURCES), sessions: z.array(importSessionSchema).min(1).max(100) })
  .strict()
  .refine((v) => new Set(v.sessions.map((s) => s.externalId)).size === v.sessions.length, "externalId duplikat dalam satu permintaan");

export type ImportSession = z.infer<typeof importSessionSchema>;

/** Dua interval [aStart, aEnd) dan [bStart, bEnd) bertabrakan bila saling memotong. */
export function overlaps(aStart: Date, aEnd: Date, bStart: Date, bEnd: Date): boolean {
  return aStart.getTime() < bEnd.getTime() && bStart.getTime() < aEnd.getTime();
}
