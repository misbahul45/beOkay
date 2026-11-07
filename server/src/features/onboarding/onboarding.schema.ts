import { z } from "zod";

export const patchOnboardingSchema = z
  .object({
    introSeen: z.literal(true).optional(),
    expectedVersion: z.number().int().min(0).optional(),
  })
  .refine((value) => value.introSeen !== undefined, "at least one change");

export type PatchOnboardingInput = z.infer<typeof patchOnboardingSchema>;
