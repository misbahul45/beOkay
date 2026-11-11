import { z } from "zod";

export const runCreateSchema = z
  .object({
    idempotencyKey: z.string().trim().min(8).max(100),
    message: z.string().trim().min(2).max(2000),
    /** Makanan yang dicari alternatifnya. Bila kosong, diturunkan dari pesan secara deterministik. */
    query: z.string().trim().min(2).max(80).optional(),
    /** Giliran lanjutan dalam percakapan: run sebelumnya milik pengguna yang sama (maks 20 giliran). */
    previousRunId: z.uuid().optional(),
    intent: z.enum(["NUTRITION_ALTERNATIVES", "ACTIVITY_PLAN"]).optional(),
    activity: z
      .object({
        maxMinutes: z.number().int().min(5).max(180).optional(),
        avoidTypes: z.array(z.enum(["walking", "cycling", "running", "strength"])).max(4).optional(),
      })
      .strict()
      .optional(),
  })
  .strict();

export const decisionSchema = z
  .object({
    operationId: z.uuid(),
    decision: z.enum(["ACCEPT", "REJECT"]),
    expectedVersion: z.number().int().min(1),
  })
  .strict();

export const feedbackSchema = z.object({ operationId: z.uuid(), kind: z.enum(["CONSUMED", "NOT_CONSUMED", "COMPLETED", "SKIPPED"]), activitySessionId: z.uuid().optional() }).strict();

export type RunCreate = z.infer<typeof runCreateSchema>;
export type Decision = z.infer<typeof decisionSchema>;
export type Feedback = z.infer<typeof feedbackSchema>;
