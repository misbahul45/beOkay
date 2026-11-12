import { z } from "zod";

export const USAGE_EVENT_TYPES = ["record_created", "screen_opened", "suggestion_offered", "suggestion_accepted", "suggestion_declined", "notification_opened", "quick_repeat_used", "context_viewed", "reflection_completed", "strategy_chosen", "vital_recorded", "lab_recorded", "form_saved", "education_opened", "voice_input_used", "guest_records_migrated"] as const;
export type UsageEventType = (typeof USAGE_EVENT_TYPES)[number];

export const USAGE_DOMAINS = ["meal", "glucose", "activity", "medication", "goal", "vital", "lab", "coaching", "assistant", "community", "notification", "home", "insights", "settings", "education", "other"] as const;
export type UsageDomain = (typeof USAGE_DOMAINS)[number];

export const CLIENT_EVENT_TYPES = ["screen_opened", "notification_opened", "quick_repeat_used", "context_viewed", "form_saved", "suggestion_offered", "education_opened", "voice_input_used", "guest_records_migrated"] as const satisfies readonly UsageEventType[];

const token = z.string().regex(/^[a-z][a-z0-9_]{0,39}$/);

export const usageMetaSchema = z
  .object({
    via: z.enum(["form", "quick", "assistant", "draft", "scan", "notification", "offline_sync", "reflection", "import", "voice", "guest"]).optional(),
    screen: token.optional(),
    durationMs: z.number().int().min(0).max(3_600_000).optional(),
    source: token.optional(),
    trigger: token.optional(),
    kind: token.optional(),
    position: z.number().int().min(0).max(50).optional(),
    shown: z.boolean().optional(),
    count: z.number().int().min(0).max(1000).optional(),
  })
  .strict();

export type UsageMeta = z.infer<typeof usageMetaSchema>;

export const clientEventSchema = z
  .object({
    type: z.enum(CLIENT_EVENT_TYPES),
    domain: z.enum(USAGE_DOMAINS).optional(),
    meta: usageMetaSchema.default({}),
    occurredAt: z.iso.datetime({ offset: true }),
  })
  .strict();

export const clientBatchSchema = z
  .object({
    appVersion: z.string().regex(/^[0-9A-Za-z.+_-]{1,40}$/).optional(),
    platform: z.enum(["android", "ios"]).optional(),
    events: z.array(clientEventSchema).min(1).max(50),
  })
  .strict();

export type ClientBatch = z.infer<typeof clientBatchSchema>;

export const MAX_CLOCK_SKEW_MS = 10 * 60_000;
export const MAX_EVENT_AGE_MS = 7 * 86_400_000;

export function acceptableTime(at: Date, now: Date) {
  const t = at.getTime();
  return Number.isFinite(t) && t <= now.getTime() + MAX_CLOCK_SKEW_MS && t >= now.getTime() - MAX_EVENT_AGE_MS;
}

export function median(values: number[]): number | null {
  if (values.length === 0) return null;
  const s = [...values].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}
