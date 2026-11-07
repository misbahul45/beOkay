import { z } from "zod";

export const DIAGNOSIS_STATUSES = ["diagnosed", "not_diagnosed", "unknown", "undisclosed"] as const;
export const DIABETES_TYPES = ["type_2", "type_1", "other", "unknown"] as const;
export const TREATMENT_CONTEXTS = ["oral_medication", "insulin", "lifestyle", "none", "undisclosed"] as const;

export type DiagnosisStatus = (typeof DIAGNOSIS_STATUSES)[number];
export type DiabetesType = (typeof DIABETES_TYPES)[number];
export type TreatmentContext = (typeof TREATMENT_CONTEXTS)[number];

const treatmentContext = z
  .array(z.enum(TREATMENT_CONTEXTS))
  .max(TREATMENT_CONTEXTS.length)
  .refine((items) => new Set(items).size === items.length, "duplicate values")
  .refine(
    (items) => items.length <= 1 || !items.some((item) => item === "none" || item === "undisclosed"),
    "none/undisclosed must stand alone",
  );

const diagnosedYear = z
  .number()
  .int()
  .min(1900)
  .refine((year) => year <= new Date().getUTCFullYear(), "future year");

const fields = {
  diagnosisStatus: z.enum(DIAGNOSIS_STATUSES),
  diabetesType: z.enum(DIABETES_TYPES).nullable(),
  diagnosedYear: diagnosedYear.nullable(),
  treatmentContext,
};

export const putHealthProfileSchema = z.object({
  diagnosisStatus: fields.diagnosisStatus,
  diabetesType: fields.diabetesType.optional(),
  diagnosedYear: fields.diagnosedYear.optional(),
  treatmentContext: fields.treatmentContext.optional(),
});

export const patchHealthProfileSchema = z
  .object({
    diagnosisStatus: fields.diagnosisStatus.optional(),
    diabetesType: fields.diabetesType.optional(),
    diagnosedYear: fields.diagnosedYear.optional(),
    treatmentContext: fields.treatmentContext.optional(),
  })
  .refine((value) => Object.values(value).some((entry) => entry !== undefined), "at least one field");

export type PutHealthProfileInput = z.infer<typeof putHealthProfileSchema>;
export type PatchHealthProfileInput = z.infer<typeof patchHealthProfileSchema>;
