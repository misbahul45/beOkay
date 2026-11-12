import { timingSafeEqual } from "node:crypto";
import { env } from "../../config/env.ts";
import { prisma } from "../database/prisma.ts";
import { metrics } from "./metrics.ts";
import { featureFlags, FEATURE_KEYS } from "../../features/feature-flags/feature-flags.service.ts";

function allowed(req: Request) {
  if (!env.METRICS_TOKEN) return env.NODE_ENV !== "production";
  const header = req.headers.get("authorization") ?? "";
  const given = Buffer.from(header.replace(/^Bearer\s+/i, ""));
  const want = Buffer.from(env.METRICS_TOKEN);
  return given.length === want.length && timingSafeEqual(given, want);
}

async function gauges() {
  const out: { name: string; help: string; labels?: Record<string, string>; value: number }[] = [];
  const outbox = await prisma.outboxEvent.groupBy({ by: ["status"], _count: { _all: true } });
  for (const s of ["PENDING", "DONE", "DEAD"]) out.push({ name: "beokay_outbox_events", help: "Outbox events by status.", labels: { status: s }, value: outbox.find((r) => r.status === s)?._count._all ?? 0 });
  const since = new Date(Date.now() - 86_400_000);
  const deliveries = await prisma.pushDelivery.groupBy({ by: ["status"], where: { attemptedAt: { gte: since } }, _count: { _all: true } });
  for (const r of deliveries) out.push({ name: "beokay_push_deliveries_24h", help: "Push deliveries in the last 24 hours by status.", labels: { status: r.status }, value: r._count._all });
  out.push({ name: "beokay_notifications_unread", help: "Unread inbox notifications.", value: await prisma.notification.count({ where: { readAt: null } }) });
  out.push({ name: "beokay_incident_reports_unemailed", help: "Incident reports not yet forwarded by email.", value: await prisma.incidentReport.count({ where: { emailedAt: null } }) });
  const flags = await featureFlags.all();
  for (const k of FEATURE_KEYS) out.push({ name: "beokay_feature_enabled", help: "Feature flag state (1 = on).", labels: { feature: k }, value: flags[k] ? 1 : 0 });
  return out;
}

export const metricsRoutes = {
  "/metrics": {
    GET: async (req: Request) => {
      if (!allowed(req)) return new Response("Not Found", { status: 404 });
      let extra: Awaited<ReturnType<typeof gauges>> = [];
      try {
        extra = await gauges();
        extra.push({ name: "beokay_database_up", help: "1 when the database answered.", value: 1 });
      } catch {
        extra = [{ name: "beokay_database_up", help: "1 when the database answered.", value: 0 }];
      }
      return new Response(metrics.render(extra), { headers: { "content-type": "text/plain; version=0.0.4; charset=utf-8", "cache-control": "no-store" } });
    },
  },
};
