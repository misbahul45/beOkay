import { z } from "zod";

export const draftConfirmSchema = z
  .object({
    expectedVersion: z.number().int().min(1),
    category: z.enum(["breakfast", "lunch", "dinner", "snack"]),
    consumedAt: z.iso.datetime({ offset: true }),
    items: z
      .array(
        z
          .object({
            index: z.number().int().min(0).max(29),
            candidateKey: z.string().trim().min(1).max(80).nullable(),
            name: z.string().trim().min(1).max(120),
            quantity: z.number().finite().positive().max(10000),
            unit: z.enum(["g", "portion", "piece", "ml"]),
            grams: z.number().finite().positive().max(100000).nullable(),
          })
          .strict(),
      )
      .min(1)
      .max(30),
  })
  .strict();

export type DraftConfirm = z.infer<typeof draftConfirmSchema>;
