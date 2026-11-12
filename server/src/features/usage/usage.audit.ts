import type { Prisma } from "../../generated/prisma/client.ts";
import { onAudit, type AuditEvent } from "../../shared/audit/audit.ts";
import { currentPolicy } from "../consent/consent.policy.ts";
import { featureFlags } from "../feature-flags/feature-flags.service.ts";
import type { UsageDomain, UsageEventType, UsageMeta } from "./usage.model.ts";

type Mapped = { type: UsageEventType; domain: UsageDomain; meta?: UsageMeta };

export function mapAudit(event: AuditEvent): Mapped | null {
  const m = (event.metadata ?? {}) as Record<string, unknown>;
  switch (event.eventType) {
    case "meal_created":
      return { type: "record_created", domain: "meal" };
    case "glucose_recorded":
      return { type: "record_created", domain: "glucose" };
    case "activity_recorded":
      return { type: "record_created", domain: "activity" };
    case "activity_imported":
      return { type: "record_created", domain: "activity", meta: { via: "import" } };
    case "medication_intake_recorded":
      return { type: "record_created", domain: "medication" };
    case "goal_checkin_recorded":
      return { type: "record_created", domain: "goal" };
    case "vital_recorded":
      return { type: "record_created", domain: "vital" };
    case "lab_recorded":
      return { type: "record_created", domain: "lab" };
    case "weekly_reflection_completed":
      return { type: "reflection_completed", domain: "coaching" };
    case "coaching_decided":
      if (m.decision === "ACCEPT") return { type: "suggestion_accepted", domain: "coaching", meta: { source: token(m.source) } };
      if (m.decision === "DECLINE") return { type: "suggestion_declined", domain: "coaching", meta: { source: token(m.source) } };
      return null;
    case "agent_recommendation_decided":
      if (m.decision === "ACCEPT" || m.decision === "ACCEPTED") return { type: "suggestion_accepted", domain: "assistant" };
      if (m.decision === "DECLINE" || m.decision === "DECLINED" || m.decision === "REJECT") return { type: "suggestion_declined", domain: "assistant" };
      return null;
    case "meal_draft_saved":
      return { type: "suggestion_accepted", domain: "meal", meta: { via: "draft" } };
    case "coaching_strategy_chosen":
      return { type: "strategy_chosen", domain: "coaching" };
    default:
      return null;
  }
}

function token(v: unknown): string | undefined {
  if (typeof v !== "string") return undefined;
  const t = v.toLowerCase();
  return /^[a-z][a-z0-9_]{0,39}$/.test(t) ? t : undefined;
}

export async function usageAuditListener(db: unknown, event: AuditEvent) {
  const mapped = mapAudit(event);
  if (!mapped) return;
  if (!(await featureFlags.isEnabled("analytics"))) return;
  const tx = db as Prisma.TransactionClient;
  const consent = await tx.consentRecord.findFirst({ where: { userId: event.userId, purpose: "product_analytics", withdrawnAt: null, policyVersion: currentPolicy.version }, select: { id: true } });
  if (!consent) return;
  const meta = Object.fromEntries(Object.entries(mapped.meta ?? {}).filter(([, v]) => v !== undefined));
  await tx.usageEvent.create({ data: { userId: event.userId, eventType: mapped.type, domain: mapped.domain, meta, platform: "server" } });
}

onAudit(usageAuditListener);
