import { z } from "zod";

const slot = z.enum(["MORNING", "MIDDAY", "AFTERNOON", "EVENING"]);
const localTime = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/);

export const decisionSchema = z
  .object({
    operationId: z.uuid(),
    decision: z.enum(["ACCEPT", "DECLINE", "WITHDRAW"]),
    slot: slot.optional(),
    reminder: z.object({ localTime: localTime.optional() }).strict().nullable().optional(),
  })
  .strict()
  .refine((v) => v.decision === "ACCEPT" || (v.slot === undefined && !v.reminder), { message: "Waktu dan pengingat hanya untuk menerima rencana." });

export const FEEDBACK_KINDS = ["HELPFUL", "NOT_HELPFUL", "ALREADY_DONE", "NOT_NOW", "TOO_FREQUENT", "PREFER_DIFFERENT_TIME", "PREFER_DIFFERENT_SUGGESTION", "STOP_THIS_TYPE"] as const;

export const feedbackSchema = z
  .object({ operationId: z.uuid(), kind: z.enum(FEEDBACK_KINDS), slot: slot.optional() })
  .strict()
  .refine((v) => (v.kind === "PREFER_DIFFERENT_TIME") === (v.slot !== undefined), { message: "Pilih waktu hanya untuk 'waktu lain'." });

export const confirmSchema = z.object({ operationId: z.uuid(), date: z.iso.date() }).strict();

export const checkinSchema = z
  .object({
    operationId: z.uuid(),
    weekStart: z.iso.date(),
    mood: z.enum(["GOOD", "MIXED", "HARD"]).optional(),
    hardest: z.array(z.enum(["TIME", "FORGOT", "ENERGY", "MOTIVATION", "OTHER"])).max(5).default([]).refine((v) => new Set(v).size === v.length, "duplikat"),
    note: z.string().trim().min(1).max(280).optional(),
    adjustments: z.array(z.object({ goalId: z.uuid(), toTarget: z.number().positive().max(1000000) }).strict()).max(5).default([]),
    preferredSlot: slot.optional(),
    rememberSlot: z.boolean().optional(),
    strategy: z.object({ barrier: z.enum(["TIME", "FORGOT", "ENERGY", "MOTIVATION", "OTHER"]), key: z.string().regex(/^[A-Z_]{3,40}$/) }).strict().optional(),
  })
  .strict()
  .refine((v) => new Set(v.adjustments.map((a) => a.goalId)).size === v.adjustments.length, { message: "Satu penyesuaian per tujuan." })
  .refine((v) => !v.strategy || v.hardest.includes(v.strategy.barrier), { message: "Strategi harus untuk hambatan yang dipilih." });

export type DecisionInput = z.infer<typeof decisionSchema>;
export type FeedbackInput = z.infer<typeof feedbackSchema>;
export type ConfirmInput = z.infer<typeof confirmSchema>;
export type CheckinInput = z.infer<typeof checkinSchema>;
