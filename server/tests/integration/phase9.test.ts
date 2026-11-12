import { afterAll, beforeAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { appRoutes } from "../../src/routes.ts";
import { J, actors, api, call, requireIsolatedApi, todayWib } from "../support/api.ts";

const { actor, cleanup } = actors();
const H = ["health_data_processing", "descriptive_summaries"];
beforeAll(requireIsolatedApi);
afterAll(cleanup);

const day = (offset: number) => new Date(Date.parse(todayWib() + "T00:00:00Z") + offset * 86_400_000).toISOString().slice(0, 10);

test("K-1 impor perangkat: setiap jenis butuh izin sendiri, idempoten, langkah diganti agregat terbaru, glukosa perangkat dihitung", async () => {
  const a = await actor(H), b = await actor(H);
  expect(await J(await call("/api/me/device-import/preferences", a.token))).toMatchObject({ workouts: false, steps: false, weight: false, glucose: false, sleep: false });
  const at = (h: number) => new Date(Date.now() - h * 3600_000).toISOString();
  const payload = {
    source: "health_connect",
    steps: [{ localDate: day(-1), steps: 7200 }, { localDate: day(0), steps: 3100 }],
    weights: [{ externalId: "hc-w-1", measuredAt: at(30), kg: 72.35 }],
    glucose: [{ externalId: "hc-g-1", measuredAt: at(3), value: 7.1, unit: "mmol/L", specimen: "capillary_blood", mealContext: "fasting" }],
    sleep: [{ externalId: "hc-s-1", startedAt: at(12), endedAt: at(5) }],
  };
  const off = await J(await call("/api/me/device-import", a.token, payload));
  expect(off.steps).toMatchObject({ upserted: 0, rejected: 2 });
  expect(off.glucose.results[0]).toMatchObject({ status: "REJECTED", reason: "DEVICE_TYPE_DISABLED" });
  expect(await prisma.glucoseObservation.count({ where: { userId: a.id } })).toBe(0);

  expect(await J(await call("/api/me/device-import/preferences", a.token, { steps: true, weight: true, glucose: true, sleep: true }, "PATCH"))).toMatchObject({ steps: true, workouts: false });
  const first = await J(await call("/api/me/device-import", a.token, payload));
  expect(first.steps).toMatchObject({ upserted: 2 });
  expect([first.weights.created, first.glucose.created, first.sleep.created]).toEqual([1, 1, 1]);
  const again = await J(await call("/api/me/device-import", a.token, { ...payload, steps: [{ localDate: day(0), steps: 5400 }, { localDate: day(-1), steps: 7200 }] }));
  expect(again.steps).toMatchObject({ upserted: 1, unchanged: 1 });
  expect([again.weights.duplicate, again.glucose.duplicate, again.sleep.duplicate]).toEqual([1, 1, 1]);
  expect((await J(await call("/api/me/device-import", a.token, { source: "health_connect", steps: [{ localDate: day(1), steps: 10 }] }))).steps.rejected).toBe(1);
  expect((await call("/api/me/device-import", a.token, { source: "health_connect", steps: [{ localDate: day(4), steps: 10 }] })).status).toBe(400);

  const g = await prisma.glucoseObservation.findFirstOrThrow({ where: { userId: a.id } });
  expect(g).toMatchObject({ source: "health_connect", sourceRecordId: "hc-g-1", qualityStatus: "device_reported", measurementType: "capillary_blood" });
  const rec = await J(await call(`/api/me/glucose/${g.id}`, a.token));
  expect(rec).toMatchObject({ source: "health_connect", valueMgDl: 127.9136, displayValue: 128 });
  const fixed = await call(`/api/me/glucose/${g.id}`, a.token, { expectedVersion: 1, reason: "periksa", qualityStatus: "user_reported", notes: "ok" }, "PATCH");
  expect(fixed.status).toBe(200);
  expect((await J(fixed)).qualityStatus).toBe("device_reported");
  const stats = await J(await call("/api/me/insights/statistics?days=7", a.token));
  expect(stats.statistics.some((s: any) => s.domain === "glucose" && s.sampleCount >= 1)).toBe(true);

  const steps = await J(await call("/api/me/steps?days=7", a.token));
  expect(steps.series.at(-1)).toMatchObject({ date: day(0), steps: 5400 });
  expect(steps.daysWithData).toBe(2);
  expect((await J(await call("/api/me/steps?days=7", b.token))).daysWithData).toBe(0);
  expect((await J(await call("/api/me/sleep?days=7", a.token))).sessions[0]).toMatchObject({ durationMinutes: 420 });
  const w = await prisma.vitalMeasurement.findFirstOrThrow({ where: { userId: a.id } });
  expect([w.source, w.externalId, w.value.toNumber()]).toEqual(["health_connect", "hc-w-1", 72.35]);

  const goal = await J(await call("/api/me/goals", a.token, { id: crypto.randomUUID(), title: "5000 langkah", goalType: "daily_steps", targetValue: 5000, period: "daily", startDate: day(-3) }));
  expect(goal.progress ?? (await J(await call(`/api/me/goals/${goal.id}`, a.token))).progress).toMatchObject({ value: 5400, method: "SUM_DEVICE_STEPS" });
  const bundle = await J(await call("/api/me/export", a.token));
  expect(bundle.counts).toMatchObject({ dailySteps: 2, sleepSessions: 1, deviceImportPreference: 1 });
});

test("S-1 /metrics: format Prometheus dengan latensi per rute, peristiwa log, antrean, dan status fitur", async () => {
  const a = await actor(H);
  await call("/api/me/today", a.token);
  const res = await fetch(api + "/metrics");
  expect(res.status).toBe(200);
  expect(res.headers.get("content-type")).toContain("text/plain");
  const text = await res.text();
  expect(text).toContain('beokay_http_requests_total{method="GET",route="/api/me/today",status="2xx"}');
  expect(text).toContain("beokay_http_request_duration_ms_bucket");
  expect(text).toMatch(/beokay_outbox_events\{status="DEAD"\} \d+/);
  expect(text).toContain('beokay_feature_enabled{feature="assistant"} 1');
  expect(text).toContain("beokay_database_up 1");
  expect(text).not.toMatch(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}/);
});

test("S-7/K-9 ringkasan dan tautan baca-saja: konfirmasi wajib, token hanya di URL, berbatas waktu, bisa dicabut, ikut consent", async () => {
  const a = await actor(H), b = await actor(H);
  await call("/api/me/glucose", a.token, { id: crypto.randomUUID(), originalValue: 131, originalUnit: "mg/dL", measuredAt: new Date(Date.now() - 3600_000).toISOString(), mealContext: "fasting" });
  const summary = await J(await call("/api/me/report-summary?days=14", a.token));
  expect(summary).toMatchObject({ version: "report-summary-v1", days: 14 });
  expect(summary.disclaimer).toContain("Bukan hasil pemeriksaan");
  expect((await call("/api/me/report-summary?days=7", a.token)).status).toBe(400);
  expect((await call("/api/me/share-links", a.token, { periodDays: 14, hours: 24 })).status).toBe(400);
  expect((await call("/api/me/share-links", a.token, { periodDays: 14, hours: 500, confirm: true })).status).toBe(400);
  const link = await J(await call("/api/me/share-links", a.token, { periodDays: 14, hours: 24, label: "Kontrol Puskesmas", confirm: true }));
  expect(link.url).toMatch(/\/s\/[A-Za-z0-9_-]{43}$/);
  const token = link.url.split("/s/")[1];
  const row = await prisma.shareLink.findUniqueOrThrow({ where: { id: link.id } });
  expect(row.tokenHash).not.toContain(token);
  const page = await fetch(`${api}/s/${token}`);
  expect(page.status).toBe(200);
  expect(page.headers.get("x-robots-tag")).toContain("noindex");
  expect(page.headers.get("content-security-policy")).toMatch(/default-src 'none'; style-src 'nonce-[A-Za-z0-9+\/=]+'/);
  expect(page.headers.get("cache-control")).toBe("no-store");
  const html = await page.text();
  expect(html).toContain("Ringkasan catatan 14 hari");
  expect(html).toContain("Fixture");
  expect((await prisma.shareLink.findUniqueOrThrow({ where: { id: link.id } })).accessCount).toBe(1);
  expect((await J(await call("/api/me/share-links", a.token))).items[0]).toMatchObject({ id: link.id, active: true, accessCount: 1 });
  expect((await call(`/api/me/share-links/${link.id}/revoke`, b.token, {})).status).toBe(404);
  expect((await fetch(`${api}/s/${"x".repeat(43)}`)).status).toBe(404);
  expect((await J(await call(`/api/me/share-links/${link.id}/revoke`, a.token, {}))).active).toBe(false);
  expect((await fetch(`${api}/s/${token}`)).status).toBe(410);
  for (let i = 0; i < 5; i++) await call("/api/me/share-links", a.token, { periodDays: 30, confirm: true });
  expect((await call("/api/me/share-links", a.token, { periodDays: 30, confirm: true })).status).toBe(422);
  const c = await actor(H);
  const l2 = await J(await call("/api/me/share-links", c.token, { periodDays: 30, confirm: true }));
  await call("/api/me/consents/withdraw", c.token, { purposes: ["descriptive_summaries"] });
  expect((await fetch(`${api}/s/${l2.url.split("/s/")[1]}`)).status).toBe(410);
  expect(await prisma.auditEvent.count({ where: { userId: a.id, eventType: { in: ["share_link_created", "share_link_viewed", "share_link_revoked"] } } })).toBeGreaterThanOrEqual(3);
});

const paramRoutes = Object.entries(appRoutes).filter(([p]) => p.includes("/:"));

test("S-10 IDOR: setiap rute GET ber-parameter menolak ID milik pengguna lain", async () => {
  const a = await actor([...H, "personalized_ai", "community_membership"]), b = await actor([...H, "personalized_ai", "community_membership"]);
  const ids: string[] = [];
  const save = async (path: string, body: object) => {
    const r = await call(path, a.token, body);
    const j = await J(r);
    if (j?.id) ids.push(j.id);
  };
  const t = new Date(Date.now() - 3600_000).toISOString();
  await save("/api/me/glucose", { id: crypto.randomUUID(), originalValue: 110, originalUnit: "mg/dL", measuredAt: t });
  await save("/api/me/meals", { id: crypto.randomUUID(), category: "lunch", consumedAt: t, items: [{ name: "Nasi", quantity: 1, unit: "portion" }] });
  await save("/api/me/activities", { id: crypto.randomUUID(), activityType: "walking", startedAt: new Date(Date.now() - 7200_000).toISOString(), durationMinutes: 20 });
  await save("/api/me/vitals", { id: crypto.randomUUID(), kind: "weight", value: 70, unit: "kg", measuredAt: t });
  await save("/api/me/labs", { id: crypto.randomUUID(), test: "hba1c", value: 7, unit: "%", sampledAt: day(-1) });
  await save("/api/me/goals", { id: crypto.randomUUID(), title: "Aktif", goalType: "activity_minutes", targetValue: 100, period: "weekly", startDate: day(-1) });
  await save("/api/me/medications", { id: crypto.randomUUID(), name: "Obat A" });
  await save("/api/me/reminders", { kind: "glucose", title: "Cek", localTime: "07:00", daysOfWeek: [1, 2, 3] });
  await save("/api/me/share-links", { periodDays: 14, confirm: true });
  const thread = crypto.randomUUID();
  await call(`/api/me/conversations/${thread}/messages`, a.token, { clientMessageId: crypto.randomUUID(), text: "halo" });
  ids.push(thread);
  expect(ids.length).toBeGreaterThanOrEqual(8);
  const leaks: string[] = [];
  for (const [pattern, handlers] of paramRoutes) {
    if (pattern.startsWith("/s/") || typeof handlers === "function" || !("GET" in handlers)) continue;
    for (const id of ids) {
      const path = pattern.replace(/:id/g, id).replace(/:[a-zA-Z]+/g, "0");
      const r = await call(path, b.token);
      if (r.status < 300 || r.status >= 500) leaks.push(`${r.status} GET ${pattern}`);
      const text = await r.text();
      if (r.status < 500 && text.includes(a.id)) leaks.push(`owner id in body: ${pattern}`);
    }
  }
  expect([...new Set(leaks)]).toEqual([]);
});

test("S-10 tanpa login: setiap rute /api/me/* menolak dengan 401 untuk semua metode", async () => {
  const bad: string[] = [];
  for (const [pattern, handlers] of Object.entries(appRoutes)) {
    if (!pattern.startsWith("/api/me/") || pattern === "/api/me/realtime") continue;
    const methods = typeof handlers === "function" ? ["GET"] : Object.keys(handlers);
    const path = pattern.replace(/:[a-zA-Z]+/g, "00000000-0000-4000-8000-000000000000");
    for (const m of methods) {
      const r = await fetch(api + path, { method: m, headers: m === "GET" ? {} : { "content-type": "application/json" }, body: m === "GET" ? undefined : "{}" });
      if (r.status !== 401) bad.push(`${r.status} ${m} ${pattern}`);
      if (!r.headers.get("content-security-policy") || r.headers.get("x-content-type-options") !== "nosniff") bad.push(`headers ${m} ${pattern}`);
    }
  }
  expect(bad).toEqual([]);
});

test("S-10 masukan tidak wajar: JSON rusak, tipe konten salah, badan besar, kueri aneh tidak pernah 500", async () => {
  const a = await actor(H);
  const raw = (path: string, init: RequestInit) => fetch(api + path, { ...init, headers: { authorization: `Bearer ${a.token}`, ...(init.headers ?? {}) } });
  expect((await raw("/api/me/glucose", { method: "POST", headers: { "content-type": "application/json" }, body: "{bad" })).status).toBe(400);
  expect((await raw("/api/me/glucose", { method: "POST", headers: { "content-type": "text/plain" }, body: "{}" })).status).toBe(415);
  expect((await raw("/api/me/glucose", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ notes: "x".repeat(70_000) }) })).status).toBe(413);
  for (const q of ["' OR 1=1 --", "%00", "../../etc/passwd", "<script>", "a".repeat(2000)]) {
    const enc = encodeURIComponent(q);
    for (const path of [`/api/foods/search?q=${enc}`, `/api/me/glucose?date=${enc}`, `/api/me/timeline?cursor=${enc}`, `/api/me/vitals?kind=${enc}`, `/api/me/steps?days=${enc}`]) {
      const r = await raw(path, {});
      expect(r.status).toBeLessThan(500);
    }
  }
});
