import { z } from "zod";
import { recordTimestamp } from "../../shared/http/record-schema.ts";
const goalFields = z.object({
  title: z.string().trim().min(1).max(120),
  goalType: z.enum(["manual_checkins", "activity_minutes", "record_meals", "record_glucose", "walking_sessions"]),
  targetValue: z.number().finite().positive().max(1000000).multipleOf(0.01),
  period: z.enum(["daily", "weekly"]),
  startDate: z.iso.date(),
  endDate: z.iso.date().nullable(),
}).strict();
export const goalCreateSchema = goalFields.extend({ id: z.uuid(), endDate: goalFields.shape.endDate.default(null) }).refine(v => !v.endDate || v.endDate >= v.startDate, "endDate precedes startDate");
export const goalPatchSchema = goalFields.partial().extend({ expectedVersion: z.number().int().positive(), reason: z.string().trim().min(1).max(300), status: z.enum(["active", "paused", "completed", "archived"]).optional() }).strict().refine(v => Object.keys(v).some(k => !["expectedVersion", "reason"].includes(k)), "no changes");
const checkinFields = z.object({ eventAt: recordTimestamp, status: z.enum(["completed", "skipped", "unknown"]), value: z.number().finite().positive().max(1000000).multipleOf(0.01), notes: z.string().trim().max(2000).nullable() }).strict();
export const checkinCreateSchema = checkinFields.extend({ id: z.uuid(), value: checkinFields.shape.value.default(1), notes: checkinFields.shape.notes.default(null) });
export const checkinPatchSchema = checkinFields.partial().extend({ expectedVersion: z.number().int().positive(), reason: z.string().trim().min(1).max(300), archived: z.boolean().optional() }).strict().refine(v => Object.keys(v).some(k => !["expectedVersion", "reason"].includes(k)), "no changes");
export const goalsQuerySchema = z.object({ status: z.enum(["active", "paused", "completed", "archived"]).optional(), cursor: z.uuid().optional(), limit: z.coerce.number().int().min(1).max(50).default(20) }).strict();
export const checkinsQuerySchema = z.object({ cursor: z.uuid().optional(), limit: z.coerce.number().int().min(1).max(50).default(20), archived: z.enum(["true", "false"]).default("false") }).strict();
export type GoalInput = z.infer<typeof goalCreateSchema>;
export type GoalPatch = z.infer<typeof goalPatchSchema>;
export type CheckinInput = z.infer<typeof checkinCreateSchema>;
export type CheckinPatch = z.infer<typeof checkinPatchSchema>;
