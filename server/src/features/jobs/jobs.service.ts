import { Prisma } from "../../generated/prisma/client.ts";
import { env } from "../../config/env.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { outbox } from "../../infrastructure/queue/outbox.ts";
import { logEvent } from "../../shared/http/logger.ts";
import { sweepOutcomes } from "../agent/agent-worker.ts";
import { outcomes } from "../agent/outcomes.ts";
import { clinicalService } from "../clinical/clinical.service.ts";
import { coachingService } from "../coaching/coaching.service.ts";
import { runChallengeLifecycle } from "../community/lifecycle.service.ts";
import { educationService } from "../education/education.service.ts";
import { featureFlags } from "../feature-flags/feature-flags.service.ts";
import { notificationService } from "../notifications/notification.service.ts";
import { createFcmClient } from "../push/fcm.client.ts";
import { dispatchDueReminders } from "../push/push-dispatcher.ts";
import { retentionService } from "../retention/retention.service.ts";

export const JOBS_VERSION = "jobs-v1";
const MIN = 60_000;
type Result = Record<string, unknown>;
export type Job = { name: string; everyMs: number; run: (now: Date) => Promise<Result> };

let fcm: ReturnType<typeof createFcmClient> | null = null;
const pushSender = () => (fcm ??= createFcmClient({ projectId: env.FCM_PROJECT_ID, serviceAccountJson: env.FCM_SERVICE_ACCOUNT_JSON }));

export const JOBS: Job[] = [
  {
    name: "outbox_drain",
    everyMs: MIN,
    run: async () => {
      const total = { done: 0, failed: 0, dead: 0, batches: 0 };
      for (let i = 0; i < 20; i++) {
        const r = await outbox.drain(outcomes.handlers);
        total.done += r.done;
        total.failed += r.failed;
        total.dead += r.dead;
        total.batches++;
        if (r.done + r.failed + r.dead === 0) break;
      }
      return total;
    },
  },
  { name: "reminder_inbox", everyMs: MIN, run: async (now) => notificationService.notifyDueReminders(now) },
  {
    name: "push_dispatch",
    everyMs: MIN,
    run: async (now) => {
      const sender = pushSender();
      if (!sender.configured) return { skipped: "FCM_NOT_CONFIGURED" };
      if (!(await featureFlags.isEnabled("push"))) return { skipped: "FLAG_OFF" };
      return dispatchDueReminders(sender, now);
    },
  },
  { name: "outcome_sweep", everyMs: 60 * MIN, run: async () => sweepOutcomes() },
  { name: "challenge_lifecycle", everyMs: 60 * MIN, run: async (now) => runChallengeLifecycle(now) },
  {
    name: "coaching_nudges",
    everyMs: 60 * MIN,
    run: async () => {
      const coaching = (await featureFlags.isEnabled("coaching")) ? await coachingService.nudgeReflections() : { skipped: "FLAG_OFF" };
      const labs = await clinicalService.remindDueLabs();
      return { coaching, labs };
    },
  },
  { name: "education_sync", everyMs: 6 * 60 * MIN, run: async () => educationService.sync() },
  { name: "retention", everyMs: 23 * 60 * MIN, run: async (now) => (await retentionService.run(undefined, now)) as unknown as Result },
];

const compact = (r: Result): Prisma.InputJsonObject => {
  const text = JSON.stringify(r, (_k, v) => (typeof v === "bigint" ? Number(v) : v));
  return (text.length <= 1800 ? JSON.parse(text) : { truncated: true, size: text.length }) as Prisma.InputJsonObject;
};

export async function claimJob(name: string, everyMs: number, now: Date): Promise<boolean> {
  const before = new Date(now.getTime() - everyMs);
  const rows = await prisma.$queryRaw<{ name: string }[]>`
    INSERT INTO job_runs (name, last_started_at, last_status, updated_at) VALUES (${name}, ${now}, 'RUNNING', ${now})
    ON CONFLICT (name) DO UPDATE SET last_started_at = EXCLUDED.last_started_at, last_status = 'RUNNING', updated_at = EXCLUDED.updated_at
    WHERE job_runs.last_started_at IS NULL OR job_runs.last_started_at <= ${before}
    RETURNING name`;
  return rows.length === 1;
}

export async function runTick(now = new Date(), opts: { only?: string[]; jobs?: Job[] } = {}) {
  const jobs = (opts.jobs ?? JOBS).filter((j) => !opts.only?.length || opts.only.includes(j.name));
  const results: { name: string; ran: boolean; status?: "OK" | "FAILED"; result?: Result; ms?: number }[] = [];
  for (const job of jobs) {
    if (!(await claimJob(job.name, job.everyMs, now))) {
      results.push({ name: job.name, ran: false });
      continue;
    }
    const started = Date.now();
    try {
      const result = await job.run(now);
      await prisma.jobRun.update({ where: { name: job.name }, data: { lastFinishedAt: new Date(), lastStatus: "OK", lastResult: compact(result), updatedAt: new Date() } });
      results.push({ name: job.name, ran: true, status: "OK", result, ms: Date.now() - started });
    } catch (e) {
      const name = e instanceof Error ? e.name : "unknown";
      logEvent("error", "job_failed", { job: job.name, name });
      await prisma.jobRun.update({ where: { name: job.name }, data: { lastFinishedAt: new Date(), lastStatus: "FAILED", lastResult: { error: name }, updatedAt: new Date() } }).catch(() => {});
      results.push({ name: job.name, ran: true, status: "FAILED", ms: Date.now() - started });
    }
  }
  const ran = results.filter((r) => r.ran);
  if (ran.length) logEvent("info", "jobs_tick", { ran: ran.map((r) => r.name).join(","), failed: ran.filter((r) => r.status === "FAILED").length });
  return { version: JOBS_VERSION, at: now.toISOString(), jobs: results };
}

export async function jobStatus() {
  const rows = await prisma.jobRun.findMany({ orderBy: { name: "asc" } });
  return rows.map((r) => ({ name: r.name, lastStartedAt: r.lastStartedAt?.toISOString() ?? null, lastFinishedAt: r.lastFinishedAt?.toISOString() ?? null, lastStatus: r.lastStatus }));
}
