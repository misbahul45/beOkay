import { z } from "zod";

const noControlCharacters = (value: string) => !/[\u0000-\u001F\u007F]/.test(value);

export const updateProfileSchema = z
  .object({
    displayName: z.string().trim().min(1).max(80).refine(noControlCharacters, "control characters").optional(),
    birthYear: z.number().int().nullable().optional(),
  })
  .refine((value) => value.displayName !== undefined || value.birthYear !== undefined, "at least one field")
  .superRefine((value, ctx) => {
    if (value.birthYear === undefined || value.birthYear === null) return;
    const year = new Date().getUTCFullYear();
    if (value.birthYear < year - 120 || value.birthYear > year) {
      ctx.addIssue({ code: "custom", path: ["birthYear"], message: "out of range" });
    }
  });

export type UpdateProfileInput = z.infer<typeof updateProfileSchema>;
