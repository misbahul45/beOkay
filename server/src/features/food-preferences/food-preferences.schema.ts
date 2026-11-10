import { z } from "zod";

export const preferenceKinds = ["allergy", "restriction", "dislike", "preference"] as const;

const term = z.string().trim().min(2).max(40);

export const preferenceCreateSchema = z
  .object({
    kind: z.enum(preferenceKinds),
    term,
    label: z.string().trim().min(2).max(60).optional(),
    notes: z.string().trim().max(300).nullable().optional(),
  })
  .strict();

export const preferencePatchSchema = z
  .object({
    expectedVersion: z.number().int().min(1),
    label: z.string().trim().min(2).max(60).optional(),
    notes: z.string().trim().max(300).nullable().optional(),
    archived: z.boolean().optional(),
  })
  .strict()
  .refine((v) => v.label !== undefined || v.notes !== undefined || v.archived !== undefined, "Tidak ada perubahan.");

export const preferenceListQuerySchema = z.object({ archived: z.enum(["true", "false"]).default("false") });

export const preferenceCheckSchema = z
  .object({
    items: z.array(z.object({ name: z.string().trim().min(1).max(120), brand: z.string().trim().max(80).nullable().optional() }).strict()).min(1).max(50),
  })
  .strict();

export type PreferenceCreate = z.infer<typeof preferenceCreateSchema>;
export type PreferencePatch = z.infer<typeof preferencePatchSchema>;
