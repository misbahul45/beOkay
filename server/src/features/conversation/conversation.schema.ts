import { z } from "zod";

export const messageCreateSchema = z
  .object({
    clientMessageId: z.uuid(),
    text: z.string().trim().min(1).max(1000),
    photo: z
      .object({
        items: z
          .array(z.object({ name: z.string().trim().min(2).max(60), confidence: z.enum(["high", "medium", "low"]) }).strict())
          .min(1)
          .max(6),
      })
      .strict()
      .optional(),
  })
  .strict();

export type MessageCreate = z.infer<typeof messageCreateSchema>;
