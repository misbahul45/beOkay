import { z } from "zod";
import { TRIGGERS } from "./intervention.policy.ts";

export const evaluateSchema = z.object({ trigger: z.enum(TRIGGERS), goalId: z.uuid().optional() }).strict();
export const responseSchema = z
  .object({ kind: z.enum(["OPENED", "USEFUL", "NOT_USEFUL", "NOT_NOW", "TOO_FREQUENT", "ALREADY_DONE", "DISMISSED", "STOP_THIS_TYPE"]), snoozeMinutes: z.number().int().min(15).max(720).optional() })
  .strict();
const minute = z.number().int().min(0).max(1439);
export const preferencesSchema = z
  .object({
    pauseForHours: z.number().int().min(1).max(24 * 30).optional(),
    resume: z.literal(true).optional(),
    quietStartMinute: minute.optional(),
    quietEndMinute: minute.optional(),
    maxPerDay: z.number().int().min(0).max(5).optional(),
    maxPerWeek: z.number().int().min(0).max(21).optional(),
    mutedTriggers: z.array(z.enum(TRIGGERS)).max(TRIGGERS.length).optional(),
  })
  .strict()
  .refine((v) => !(v.pauseForHours && v.resume), { message: "Pilih jeda atau lanjutkan, bukan keduanya." });
export type EvaluateInput = z.infer<typeof evaluateSchema>;
export type ResponseInput = z.infer<typeof responseSchema>;
export type PreferencesInput = z.infer<typeof preferencesSchema>;
