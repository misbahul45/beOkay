import { z } from "zod";

export const SYNC_DOMAINS = ["meal", "glucose", "activity", "medication_intake", "goal_checkin"] as const;
export type SyncDomain = (typeof SYNC_DOMAINS)[number];

export const syncOperationSchema = z
  .object({
    operationId: z.uuid(),
    domain: z.enum(SYNC_DOMAINS),
    recordId: z.uuid(),
    operationType: z.enum(["create", "update"]),
    parentId: z.uuid().optional(),
    payload: z.record(z.string(), z.unknown()),
  })
  .strict();

export const syncRequestSchema = z
  .object({ operations: z.array(syncOperationSchema).min(1).max(50) })
  .strict()
  .refine(
    (v) => new Set(v.operations.map((o) => o.operationId)).size === v.operations.length,
    "operationId duplikat dalam satu permintaan",
  );

export type SyncOperationInput = z.infer<typeof syncOperationSchema>;
