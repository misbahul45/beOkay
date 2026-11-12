import { z } from "zod";
import { recordTimestamp } from "../../shared/http/record-schema.ts";
import { LAB_TESTS, VITAL_KINDS } from "./clinical.model.ts";

const decimal = z.number().finite().positive().max(100000).multipleOf(0.001);
const notes = z.string().trim().max(2000).nullable();

export const vitalFields = z
  .object({
    kind: z.enum(VITAL_KINDS),
    value: decimal,
    value2: decimal.nullable(),
    unit: z.enum(["kg", "cm", "mmHg"]),
    measuredAt: recordTimestamp,
    source: z.literal("manual"),
    notes,
  })
  .strict();

export const vitalCreateSchema = vitalFields.extend({ id: z.uuid(), value2: vitalFields.shape.value2.default(null), source: vitalFields.shape.source.default("manual"), notes: notes.default(null) });
export const vitalPatchSchema = vitalFields
  .omit({ kind: true, source: true })
  .partial()
  .extend({ expectedVersion: z.number().int().positive(), reason: z.string().trim().min(1).max(300), archived: z.boolean().optional() })
  .strict()
  .refine((v) => Object.keys(v).some((k) => !["expectedVersion", "reason"].includes(k)), "no changes");

const sampledAt = z.iso.date().refine((d) => d >= "1990-01-01" && Date.parse(d + "T00:00:00Z") <= Date.now() + 86_400_000, "invalid sample date");

export const labFields = z
  .object({
    test: z.enum(LAB_TESTS),
    value: decimal,
    unit: z.enum(["%", "mmol/mol", "mg/dL", "mmol/L", "umol/L", "mL/min/1.73m2", "mg/g", "mg/mmol"]),
    sampledAt,
    labName: z.string().trim().min(1).max(120).nullable(),
    source: z.enum(["manual", "lab_report"]),
    notes,
  })
  .strict();

export const labCreateSchema = labFields.extend({ id: z.uuid(), labName: labFields.shape.labName.default(null), source: labFields.shape.source.default("manual"), notes: notes.default(null) });
export const labPatchSchema = labFields
  .omit({ test: true })
  .partial()
  .extend({ expectedVersion: z.number().int().positive(), reason: z.string().trim().min(1).max(300), archived: z.boolean().optional() })
  .strict()
  .refine((v) => Object.keys(v).some((k) => !["expectedVersion", "reason"].includes(k)), "no changes");

export const vitalQuerySchema = z.object({ kind: z.enum(VITAL_KINDS).optional(), cursor: z.uuid().optional(), limit: z.coerce.number().int().min(1).max(50).default(20), archived: z.enum(["true", "false"]).default("false") }).strict();
export const labQuerySchema = z.object({ test: z.enum(LAB_TESTS).optional(), cursor: z.uuid().optional(), limit: z.coerce.number().int().min(1).max(50).default(20), archived: z.enum(["true", "false"]).default("false") }).strict();

export type VitalInput = z.infer<typeof vitalCreateSchema>;
export type VitalPatch = z.infer<typeof vitalPatchSchema>;
export type LabInput = z.infer<typeof labCreateSchema>;
export type LabPatch = z.infer<typeof labPatchSchema>;
