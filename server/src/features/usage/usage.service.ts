import { background } from "../../shared/runtime/background.ts";
import "./usage.audit.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { logEvent } from "../../shared/http/logger.ts";
import { rateWindow } from "../../shared/http/rate-window.ts";
import { AppError } from "../../shared/errors/app-error.ts";
import { consentService } from "../consent/consent.service.ts";
import { featureFlags } from "../feature-flags/feature-flags.service.ts";
import { acceptableTime, type ClientBatch, type UsageDomain, type UsageEventType, type UsageMeta } from "./usage.model.ts";

const batches = rateWindow(60_000, 30);

async function allowed(userId: string) {
  if (!(await featureFlags.isEnabled("analytics"))) return false;
  try {
    await consentService.requireConsent(userId, "product_analytics");
    return true;
  } catch {
    return false;
  }
}

export const usageService = {
  allowed,

  async record(userId: string, type: UsageEventType, domain: UsageDomain | null = null, meta: UsageMeta = {}) {
    if (!(await allowed(userId))) return false;
    await prisma.usageEvent.create({ data: { userId, eventType: type, domain, meta, platform: "server" } });
    return true;
  },

  track(userId: string, type: UsageEventType, domain: UsageDomain | null = null, meta: UsageMeta = {}) {
    background(this.record(userId, type, domain, meta).catch((e) => logEvent("warn", "usage_event_failed", { name: e instanceof Error ? e.name : "unknown" })), "usage_event");
  },

  async ingest(userId: string, batch: ClientBatch, now = new Date()) {
    if (batches.full(userId, now.getTime())) throw new AppError(429, "USAGE_RATE_LIMITED", "Terlalu banyak data pemakaian. Coba lagi sebentar lagi.");
    batches.record(userId, now.getTime());
    if (!(await allowed(userId))) return { accepted: 0, dropped: batch.events.length, recorded: false };
    const rows = batch.events
      .map((e) => ({ e, at: new Date(e.occurredAt) }))
      .filter(({ at }) => acceptableTime(at, now))
      .map(({ e, at }) => ({ userId, eventType: e.type, domain: e.domain ?? null, meta: e.meta, appVersion: batch.appVersion ?? null, platform: batch.platform ?? null, occurredAt: at }));
    if (rows.length) await prisma.usageEvent.createMany({ data: rows });
    return { accepted: rows.length, dropped: batch.events.length - rows.length, recorded: true };
  },

  async mine(userId: string) {
    const [count, first, byType] = await Promise.all([
      prisma.usageEvent.count({ where: { userId } }),
      prisma.usageEvent.findFirst({ where: { userId }, orderBy: { occurredAt: "asc" }, select: { occurredAt: true } }),
      prisma.usageEvent.groupBy({ by: ["eventType"], where: { userId }, _count: { _all: true } }),
    ]);
    return {
      recording: await allowed(userId),
      count,
      since: first?.occurredAt.toISOString() ?? null,
      byType: Object.fromEntries(byType.map((r) => [r.eventType, r._count._all])),
      notice: "Hanya jenis peristiwa, domain, dan waktu yang dicatat. Isi catatan kesehatanmu tidak pernah ikut.",
    };
  },

  async forget(userId: string) {
    const r = await prisma.usageEvent.deleteMany({ where: { userId } });
    return { deleted: r.count };
  },
};
