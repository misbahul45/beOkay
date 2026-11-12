import { env } from "../../config/env.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { logEvent } from "../../shared/http/logger.ts";

export const RETENTION_POLICY_VERSION = "retention-v1";
const DAY = 86_400_000;

export type RetentionConfig = { agentEventsDays: number; readNotificationsDays: number; auditDays: number; usageDays: number; outboxDays: number };

export const defaultRetention = (): RetentionConfig => ({
  agentEventsDays: env.RETENTION_AGENT_EVENTS_DAYS,
  readNotificationsDays: env.RETENTION_READ_NOTIFICATIONS_DAYS,
  auditDays: env.RETENTION_AUDIT_DAYS,
  usageDays: env.RETENTION_USAGE_DAYS,
  outboxDays: env.RETENTION_OUTBOX_DAYS,
});

export function cutoffs(cfg: RetentionConfig, now: Date) {
  const before = (days: number) => new Date(now.getTime() - days * DAY);
  return {
    agentEvents: before(cfg.agentEventsDays),
    readNotifications: before(cfg.readNotificationsDays),
    audit: before(cfg.auditDays),
    usage: before(cfg.usageDays),
    outbox: before(cfg.outboxDays),
    expiredMemories: before(30),
  };
}

export const retentionService = {
  async counts(cfg = defaultRetention(), now = new Date()) {
    const c = cutoffs(cfg, now);
    const [agentRunEvents, notifications, auditEvents, usageEvents, outboxEvents, routerProposals, expiredMemories] = await Promise.all([
      prisma.agentRunEvent.count({ where: { createdAt: { lt: c.agentEvents } } }),
      prisma.notification.count({ where: { readAt: { not: null, lt: c.readNotifications } } }),
      prisma.auditEvent.count({ where: { occurredAt: { lt: c.audit } } }),
      prisma.usageEvent.count({ where: { occurredAt: { lt: c.usage } } }),
      prisma.outboxEvent.count({ where: { status: "DONE", processedAt: { lt: c.outbox } } }),
      prisma.routerProposal.count({ where: { createdAt: { lt: c.agentEvents } } }),
      prisma.memoryItem.count({ where: { expiresAt: { lt: c.expiredMemories } } }),
    ]);
    return { agentRunEvents, notifications, auditEvents, usageEvents, outboxEvents, routerProposals, expiredMemories };
  },

  async run(cfg = defaultRetention(), now = new Date(), opts: { dryRun?: boolean } = {}) {
    if (opts.dryRun) return { dryRun: true, policy: RETENTION_POLICY_VERSION, config: cfg, wouldDelete: await this.counts(cfg, now) };
    const c = cutoffs(cfg, now);
    const [agentRunEvents, notifications, auditEvents, usageEvents, outboxEvents, routerProposals, expiredMemories] = await prisma.$transaction([
      prisma.agentRunEvent.deleteMany({ where: { createdAt: { lt: c.agentEvents } } }),
      prisma.notification.deleteMany({ where: { readAt: { not: null, lt: c.readNotifications } } }),
      prisma.auditEvent.deleteMany({ where: { occurredAt: { lt: c.audit } } }),
      prisma.usageEvent.deleteMany({ where: { occurredAt: { lt: c.usage } } }),
      prisma.outboxEvent.deleteMany({ where: { status: "DONE", processedAt: { lt: c.outbox } } }),
      prisma.routerProposal.deleteMany({ where: { createdAt: { lt: c.agentEvents } } }),
      prisma.memoryItem.deleteMany({ where: { expiresAt: { lt: c.expiredMemories } } }),
    ]);
    const deleted = { agentRunEvents: agentRunEvents.count, notifications: notifications.count, auditEvents: auditEvents.count, usageEvents: usageEvents.count, outboxEvents: outboxEvents.count, routerProposals: routerProposals.count, expiredMemories: expiredMemories.count };
    await prisma.auditEvent.create({ data: { userId: null, eventType: "retention_applied", metadata: { policy: RETENTION_POLICY_VERSION, ...deleted } } });
    return { dryRun: false, policy: RETENTION_POLICY_VERSION, config: cfg, deleted };
  },
};

export function startRetentionWorker(intervalMs = 6 * 60 * 60_000) {
  let lastRun = 0;
  let running = false;
  const tick = async () => {
    if (running || Date.now() - lastRun < 23 * 60 * 60_000) return;
    running = true;
    try {
      const r = await retentionService.run();
      lastRun = Date.now();
      logEvent("info", "retention_applied", r.deleted ?? {});
    } catch (e) {
      logEvent("error", "retention_failed", { name: e instanceof Error ? e.name : "unknown" });
    } finally {
      running = false;
    }
  };
  const first = setTimeout(tick, 60_000);
  const timer = setInterval(tick, intervalMs);
  return {
    stop() {
      clearTimeout(first);
      clearInterval(timer);
    },
  };
}
