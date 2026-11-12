import { env } from "../../src/config/env.ts";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { smtpEmailSender } from "../../src/infrastructure/email/smtp-email-sender.ts";
import { LATENCY_BUCKETS_MS, parsePrometheus } from "../../src/infrastructure/observability/metrics.ts";

export const SLO = { p95Ms: 800, outboxDead: 0, pushFailureRate: 0.05 };

const api = process.argv.find((a) => a.startsWith("--api="))?.slice(6) ?? process.env.API_INTERNAL_URL ?? `http://127.0.0.1:${env.PORT}`;
const dry = process.argv.includes("--dry-run");

async function latency() {
  const res = await fetch(`${api}/metrics`, { headers: env.METRICS_TOKEN ? { authorization: `Bearer ${env.METRICS_TOKEN}` } : {} });
  if (!res.ok) return { ok: false as const, status: res.status };
  const samples = parsePrometheus(await res.text());
  const buckets = new Map<string, number>();
  let count = 0;
  for (const s of samples) {
    if (s.name === "beokay_http_request_duration_ms_bucket" && s.labels.le !== "+Inf") buckets.set(s.labels.le!, (buckets.get(s.labels.le!) ?? 0) + s.value);
    if (s.name === "beokay_http_request_duration_ms_count") count += s.value;
  }
  let p95: number | null = null;
  if (count > 0) {
    p95 = Number.POSITIVE_INFINITY;
    for (const b of LATENCY_BUCKETS_MS) if ((buckets.get(String(b)) ?? 0) >= count * 0.95) {
      p95 = b;
      break;
    }
  }
  const errors = samples.filter((s) => s.name === "beokay_log_events_total" && s.labels.level === "error").reduce((n, s) => n + s.value, 0);
  return { ok: true as const, p95, requests: count, errorEvents: errors };
}

try {
  const problems: string[] = [];
  const lat = await latency().catch((e) => ({ ok: false as const, status: String(e) }));
  if (!lat.ok) problems.push(`/metrics tidak bisa dibaca (${lat.status})`);
  else if (lat.p95 !== null && lat.p95 > SLO.p95Ms) problems.push(`p95 latensi ${lat.p95} ms > ${SLO.p95Ms} ms (sejak proses start, ${lat.requests} permintaan)`);
  const dead = await prisma.outboxEvent.count({ where: { status: "DEAD" } });
  if (dead > SLO.outboxDead) problems.push(`outbox DEAD = ${dead}`);
  const since = new Date(Date.now() - 86_400_000);
  const deliveries = await prisma.pushDelivery.groupBy({ by: ["status"], where: { attemptedAt: { gte: since } }, _count: { _all: true } });
  const settled = deliveries.filter((d) => d.status !== "pending");
  const total = settled.reduce((n, d) => n + d._count._all, 0);
  const failed = settled.filter((d) => d.status !== "sent").reduce((n, d) => n + d._count._all, 0);
  if (total >= 20 && failed / total > SLO.pushFailureRate) problems.push(`push gagal ${failed}/${total} dalam 24 jam`);
  const unemailed = await prisma.incidentReport.count({ where: { emailedAt: null, category: "adverse_event" } });
  if (unemailed > 0) problems.push(`${unemailed} laporan kejadian belum terkirim ke surel`);
  const report = { checkedAt: new Date().toISOString(), api, slo: SLO, latency: lat, outboxDead: dead, push24h: { total, failed }, problems };
  console.log(JSON.stringify(report, null, 2));
  if (problems.length && !dry && env.ALERT_EMAIL_TO) {
    await smtpEmailSender.send({ to: env.ALERT_EMAIL_TO, subject: `[beOkay] ${problems.length} alarm operasional`, text: problems.map((p) => `- ${p}`).join("\n"), html: `<ul>${problems.map((p) => `<li>${p.replace(/[<>&]/g, "")}</li>`).join("")}</ul>` });
  }
  process.exitCode = problems.length ? 1 : 0;
} finally {
  await prisma.$disconnect();
}
