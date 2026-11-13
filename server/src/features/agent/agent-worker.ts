import { prisma } from "../../infrastructure/database/prisma.ts";
import { outbox } from "../../infrastructure/queue/outbox.ts";
import { eventHandlers } from "../events/handlers.ts";
import { logEvent } from "../../shared/http/logger.ts";
import { OUTCOME_WINDOW_DAYS, outcomes } from "./outcomes.ts";

const DRAIN_MS = 3_000;
const SWEEP_MS = 60_000;

/** Pengguna yang punya rencana diterima tanpa hasil terukur dalam jendela waktu. */
export async function usersWithOpenPlans(limit = 50): Promise<string[]> {
  const since = new Date(Date.now() - OUTCOME_WINDOW_DAYS * 86_400_000);
  const [meals, acts] = await Promise.all([
    prisma.plannedMeal.findMany({ where: { createdAt: { gte: since }, recommendation: { outcome: null } }, distinct: ["userId"], select: { userId: true }, take: limit }),
    prisma.activityPlan.findMany({ where: { createdAt: { gte: since }, recommendation: { outcome: null } }, distinct: ["userId"], select: { userId: true }, take: limit }),
  ]);
  return [...new Set([...meals, ...acts].map((r) => r.userId))].slice(0, limit);
}

export async function sweepOutcomes(): Promise<{ users: number; observed: number; retracted: number }> {
  let observed = 0, retracted = 0;
  const users = await usersWithOpenPlans();
  for (const userId of users) {
    const r = await outcomes.reconcile(userId);
    observed += r.observed;
    retracted += r.retracted;
  }
  return { users: users.length, observed, retracted };
}

/** Pekerja dalam proses: menguras outbox tiap beberapa detik dan menyapu hasil terukur tiap menit. Aman dijalankan di beberapa instans (SKIP LOCKED + kunci unik). */
export function startAgentWorker() {
  let busy = false;
  const tick = async () => {
    if (busy) return;
    busy = true;
    try {
      const r = await outbox.drain(eventHandlers());
      if (r.done + r.failed + r.dead > 0) logEvent("info", "outbox_drained", r);
    } catch (e) {
      logEvent("error", "outbox_drain_failed", { name: e instanceof Error ? e.name : "unknown" });
    } finally {
      busy = false;
    }
  };
  const sweep = async () => {
    try {
      const r = await sweepOutcomes();
      if (r.observed + r.retracted > 0) logEvent("info", "outcomes_swept", r);
    } catch (e) {
      logEvent("error", "outcome_sweep_failed", { name: e instanceof Error ? e.name : "unknown" });
    }
  };
  const a = setInterval(tick, DRAIN_MS);
  const b = setInterval(sweep, SWEEP_MS);
  return { stop() { clearInterval(a); clearInterval(b); } };
}
