import type { OutboxEvent, OutboxHandlers } from "../../infrastructure/queue/outbox.ts";
import { logEvent } from "../../shared/http/logger.ts";
import { outcomes } from "../agent/outcomes.ts";
import { dailyFacts } from "../projections/daily-facts.service.ts";
import { consentService } from "../consent/consent.service.ts";
import { memoryService } from "../memory/memory.service.ts";

type Handler = (event: OutboxEvent) => Promise<void>;
type Subscription = { name: string; handle: Handler };

const registry = new Map<string, Subscription[]>();

export function subscribe(type: string, name: string, handle: Handler) {
  const list = registry.get(type) ?? [];
  if (list.some((s) => s.name === name)) throw new Error(`DUPLICATE_SUBSCRIPTION:${type}:${name}`);
  list.push({ name, handle });
  registry.set(type, list);
}

export function subscriptions(): Record<string, string[]> {
  return Object.fromEntries([...registry.entries()].map(([t, subs]) => [t, subs.map((s) => s.name)]));
}

const localDatesOf = (ev: OutboxEvent) => (Array.isArray(ev.payload.localDates) ? (ev.payload.localDates as unknown[]).filter((d): d is string => typeof d === "string" && /^\d{4}-\d{2}-\d{2}$/.test(d)) : []);

const OUTCOME_KINDS = new Set(["meal", "activity"]);

let installed = false;
export function installDefaultSubscriptions(extra: (sub: typeof subscribe) => void = () => {}) {
  if (installed) return;
  installed = true;
  for (const [type, fn] of Object.entries(outcomes.handlers)) subscribe(type, "agent.outcomes", fn);
  for (const action of ["created", "corrected", "archived"]) {
    subscribe(`record.${action}`, "projections.daily_facts", async (ev) => {
      if (ev.userId) await dailyFacts.onRecordEvent(ev.userId, localDatesOf(ev));
    });
    if (action === "created") {
      subscribe("record.created", "memory.derived_activity_time", async (ev) => {
        if (ev.userId && ev.payload.kind === "activity") await memoryService.proposeDerived(ev.userId);
      });
    }
    subscribe(`record.${action}`, "agent.outcome_reconcile", async (ev) => {
      if (ev.userId && OUTCOME_KINDS.has(String(ev.payload.kind)) && (await consentService.hasConsent(ev.userId, "personalized_ai"))) await outcomes.reconcile(ev.userId);
    });
  }
  for (const type of ["device.imported", "journey.changed", "consent.granted", "memory.changed", "challenge.joined", "challenge.left", "challenge.scored"]) {
    subscribe(type, "audit.log", async (ev) => {
      logEvent("info", "domain_event", { type: ev.type });
    });
  }
  extra(subscribe);
}

export function eventHandlers(): OutboxHandlers {
  installDefaultSubscriptions();
  return Object.fromEntries(
    [...registry.entries()].map(([type, subs]) => [
      type,
      async (ev: OutboxEvent) => {
        for (const s of subs) await s.handle(ev);
      },
    ]),
  );
}
