import { z } from "zod";

export const messageCreateSchema = z
  .object({
    clientMessageId: z.uuid(),
    text: z.string().trim().min(1).max(1000),
  })
  .strict();

export type MessageCreate = z.infer<typeof messageCreateSchema>;
