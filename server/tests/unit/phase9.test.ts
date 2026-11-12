import { expect, test } from "bun:test";
import { dailyStepsAdjustment, percentile } from "../../src/features/coaching/coaching.model.ts";
import { deviceImportSchema } from "../../src/features/devices/device-import.schema.ts";
import { renderSummary, renderUnavailable } from "../../src/features/share/share.page.ts";
import { metrics, normalizePath, p95FromBuckets, parsePrometheus } from "../../src/infrastructure/observability/metrics.ts";
import { applySecurityHeaders } from "../../src/shared/http/security-headers.ts";

test("Metrik: rute dinormalisasi tanpa ID, histogram dan p95, keluaran Prometheus bisa dibaca ulang", () => {
  expect(normalizePath("/api/me/glucose/0b8a4f6e-2c1d-4e5f-9a7b-1c2d3e4f5a6b/revisions")).toBe("/api/me/glucose/:id/revisions");
  expect(normalizePath("/s/abcDEF123")).toBe("/s/:token");
  expect(normalizePath("/api/auth/sign-in/email")).toBe("/api/auth/*");
  metrics.reset();
  for (let i = 0; i < 19; i++) metrics.observeRequest("GET", "/api/me/today", 200, 30);
  metrics.observeRequest("GET", "/api/me/today", 500, 3000);
  metrics.countEvent("error", "ml_shadow_failed");
  const snap = metrics.snapshot();
  expect(p95FromBuckets(snap.latency.get("GET|/api/me/today")!)).toBe(50);
  const parsed = parsePrometheus(metrics.render([{ name: "beokay_outbox_events", help: "x", labels: { status: "DEAD" }, value: 2 }]));
  expect(parsed.find((s) => s.name === "beokay_http_requests_total" && s.labels.status === "5xx")?.value).toBe(1);
  expect(parsed.find((s) => s.name === "beokay_log_events_total" && s.labels.event === "ml_shadow_failed")?.value).toBe(1);
  expect(parsed.find((s) => s.name === "beokay_outbox_events")?.value).toBe(2);
  expect(parsed.some((s) => s.name === "beokay_http_request_duration_ms_bucket" && s.labels.le === "+Inf" && s.value === 20)).toBe(true);
  metrics.reset();
});

test("Impor perangkat: batas skema per jenis data", () => {
  const now = new Date(Date.now() - 60_000).toISOString();
  expect(deviceImportSchema.safeParse({ source: "health_connect" }).success).toBe(false);
  expect(deviceImportSchema.safeParse({ source: "health_connect", steps: [{ localDate: "2026-11-10", steps: 8000 }] }).success).toBe(true);
  expect(deviceImportSchema.safeParse({ source: "health_connect", steps: [{ localDate: "2026-11-10", steps: -1 }] }).success).toBe(false);
  expect(deviceImportSchema.safeParse({ source: "apple_health", steps: [{ localDate: "2026-11-10", steps: 1 }] }).success).toBe(false);
  expect(deviceImportSchema.safeParse({ source: "health_connect", glucose: [{ externalId: "g", measuredAt: now, value: 6.2, unit: "mmol/L" }] }).data?.glucose[0]).toMatchObject({ specimen: "unknown", mealContext: "unknown" });
  expect(deviceImportSchema.safeParse({ source: "health_connect", weights: [{ externalId: "w", measuredAt: now, kg: 5 }] }).success).toBe(false);
});

test("Tujuan langkah harian: persentil 60 dari 10 hari, naik ≤ 10% bila sering tercapai, turun ≤ 10% bila jauh di bawah", () => {
  const g = { id: "g", title: "8000 langkah", target: 8000, version: 1 };
  expect(percentile([9000, 8500, 8200, 9500, 8800, 7000, null as unknown as number].filter((v) => v !== null), 0.6)).toBeGreaterThan(8000);
  expect(dailyStepsAdjustment(g, [9000, 8500, 8200, 9500, 8800, 7000, null, null, 8600, 9100])).toMatchObject({ direction: "UP", toTarget: 8800 });
  expect(dailyStepsAdjustment(g, [3000, 2500, 4000, 3500, 2800, null, null, null, null, null])).toMatchObject({ direction: "DOWN", toTarget: 7200 });
  expect(dailyStepsAdjustment(g, [8000, 7900, 8100, null, null, null, null, null, null, null])).toBeNull();
  expect(dailyStepsAdjustment(g, [7000, 7500, 8100, 7900, 8000, 7600])).toBeNull();
});

test("Halaman baca-saja: isi di-escape, kedaluwarsa jelas, header halaman tanpa skrip dan tidak diindeks", () => {
  const html = renderSummary(
    {
      version: "report-summary-v1",
      generatedAt: "2026-11-12T00:00:00Z",
      generatedLocal: { localDate: "2026-11-12", localTime: "07:00", timezone: "Asia/Jakarta" },
      timezone: "Asia/Jakarta",
      person: { name: "<script>alert(1)</script>", diabetesType: "type_2", diagnosedYear: 2019 },
      period: { start: "2026-10-14", end: "2026-11-12", days: 30 },
      days: 30,
      glucoseUnit: "mg/dL",
      statistics: [{ id: "glucose.fasting_median", domain: "glucose", label: "Median glukosa puasa", value: 128, unit: "mg/dL", state: "READY", sampleCount: 9, sampleUnit: "pengukuran", coverage: { status: "PARTIAL", daysWithData: 9, totalDays: 30 }, limitations: [] }],
      steps: { daysWithData: 0, medianSteps: null },
      vitals: [{ label: "Berat badan", value: "72 kg", date: "2026-11-10", change: null }],
      labs: [],
      medications: [{ name: "Metformin", strength: "500 mg", instructions: "2x sehari" }],
      disclaimer: "Bukan diagnosis.",
    } as any,
    new Date("2026-11-15T00:00:00Z"),
  );
  expect(html).not.toContain("<script>");
  expect(html).toContain("&lt;script&gt;");
  expect(html).toContain("Median glukosa puasa");
  expect(html).toContain("Metformin");
  expect(html).toContain("2026-11-15 00:00");
  expect(renderUnavailable(410)).toContain("kedaluwarsa");
  const h = new Headers();
  applySecurityHeaders(h, { noStore: true, page: true, production: true });
  expect(h.get("Content-Security-Policy")).toContain("default-src 'none'");
  expect(h.get("Content-Security-Policy")).not.toContain("script-src");
  expect(h.get("X-Robots-Tag")).toContain("noindex");
  expect(h.get("Strict-Transport-Security")).toContain("max-age");
  const api = new Headers();
  applySecurityHeaders(api, { noStore: true });
  expect(api.get("Strict-Transport-Security")).toBeNull();
  expect(api.get("Content-Security-Policy")).toBe("default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'");
});
