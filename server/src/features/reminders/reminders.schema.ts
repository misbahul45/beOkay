import { z } from "zod";
import { REMINDER_KINDS } from "./reminders.model.ts";

const localTime = z.string().regex(/^([01][0-9]|2[0-3]):[0-5][0-9]$/, "Format jam HH:MM.");
const days = z
  .array(z.number().int().min(1).max(7))
  .min(1)
  .max(7)
  .transform((d) => [...new Set(d)].sort((a, b) => a - b));

export const reminderCreateSchema = z
  .object({ kind: z.enum(REMINDER_KINDS), title: z.string().trim().min(1).max(80), localTime, daysOfWeek: days.default([1, 2, 3, 4, 5, 6, 7]), enabled: z.boolean().default(true) })
  .strict();

export const reminderPatchSchema = z
  .object({
    expectedVersion: z.number().int().min(1),
    title: z.string().trim().min(1).max(80).optional(),
    localTime: localTime.optional(),
    daysOfWeek: days.optional(),
    enabled: z.boolean().optional(),
    archived: z.boolean().optional(),
  })
  .strict()
  .refine((v) => Object.keys(v).some((k) => k !== "expectedVersion"), "Tidak ada perubahan.");

export const reminderUpcomingQuerySchema = z.object({
  days: z.coerce.number().int().min(1).max(14).default(3),
});

export type ReminderCreate = z.infer<typeof reminderCreateSchema>;
export type ReminderPatch = z.infer<typeof reminderPatchSchema>;
