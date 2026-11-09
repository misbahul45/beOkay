import { z } from "zod";
import { recordTimestamp } from "../../shared/http/record-schema.ts";
import { validTimezone } from "./medication.model.ts";
// A scheduled occurrence may be later today; only an actual intake time must not be in the future.
const scheduledTimestamp = z.iso.datetime({ offset: true });
const text = (max: number) => z.string().trim().min(1).max(max);
const regimenFields = z.object({
  name: text(120),
  strength: text(60).nullable(),
  dosageForm: text(60).nullable(),
  dosingInstructions: text(500).nullable(),
  startDate: z.iso.date().nullable(),
  endDate: z.iso.date().nullable(),
}).strict();
export const regimenCreateSchema = regimenFields
  .extend({ id: z.uuid(), strength: regimenFields.shape.strength.default(null), dosageForm: regimenFields.shape.dosageForm.default(null), dosingInstructions: regimenFields.shape.dosingInstructions.default(null), startDate: regimenFields.shape.startDate.default(null), endDate: regimenFields.shape.endDate.default(null) })
  .refine((v) => !v.startDate || !v.endDate || v.endDate >= v.startDate, "endDate precedes startDate");
const changes = (v: object) => Object.keys(v).some((k) => !["expectedVersion", "reason"].includes(k));
export const regimenPatchSchema = regimenFields.partial().extend({ status: z.enum(["active", "paused", "inactive"]).optional(), expectedVersion: z.number().int().positive(), reason: text(300) }).strict().refine(changes, "no changes");
const scheduleFields = z.object({
  localTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
  timezone: z.string().max(64).refine(validTimezone, "invalid IANA timezone"),
  daysOfWeek: z.array(z.number().int().min(1).max(7)).min(1).max(7).refine((d) => new Set(d).size === d.length, "duplicate weekday"),
  effectiveFrom: z.iso.date(),
}).strict();
export const scheduleCreateSchema = scheduleFields.extend({ id: z.uuid() });
export const schedulePatchSchema = scheduleFields.partial().extend({ enabled: z.boolean().optional() }).strict().refine((v) => Object.keys(v).length > 0, "no changes");
const intakeFields = z.object({
  status: z.enum(["taken", "skipped", "unknown"]),
  takenAt: recordTimestamp.nullable(),
  notes: z.string().trim().max(1000).nullable(),
}).strict();
export const intakeCreateSchema = intakeFields
  .extend({ id: z.uuid(), scheduleId: z.uuid().nullable().default(null), scheduledAt: scheduledTimestamp.nullable().default(null), takenAt: intakeFields.shape.takenAt.default(null), notes: intakeFields.shape.notes.default(null) })
  .refine((v) => (v.scheduleId === null) === (v.scheduledAt === null), "scheduleId and scheduledAt go together");
export const intakePatchSchema = intakeFields.partial().extend({ archived: z.boolean().optional(), expectedVersion: z.number().int().positive(), reason: text(300) }).strict().refine(changes, "no changes");
export const listQuerySchema = z.object({ cursor: z.uuid().optional(), limit: z.coerce.number().int().min(1).max(50).default(20), status: z.enum(["active", "paused", "inactive"]).optional(), archived: z.enum(["true", "false"]).default("false") }).strict();
export const todayQuerySchema = z.object({ date: z.iso.date().optional() }).strict();
export type RegimenInput = z.infer<typeof regimenCreateSchema>;
export type RegimenPatch = z.infer<typeof regimenPatchSchema>;
export type ScheduleInput = z.infer<typeof scheduleCreateSchema>;
export type SchedulePatch = z.infer<typeof schedulePatchSchema>;
export type IntakeInput = z.infer<typeof intakeCreateSchema>;
export type IntakePatch = z.infer<typeof intakePatchSchema>;
