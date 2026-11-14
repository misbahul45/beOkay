import { afterAll, beforeAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { dailyFacts } from "../../src/features/projections/daily-facts.service.ts";
import { deviceImportService } from "../../src/features/devices/device-import.service.ts";
import { J, actors, call, requireIsolatedApi, todayWib } from "../support/api.ts";

const { actor, cleanup } = actors();
const H = ["health_data_processing", "descriptive_summaries"];
beforeAll(requireIsolatedApi);
afterAll(cleanup);

const STEP = 300_000;
const bucketAt = (minutesAgo: number) => new Date(Math.floor((Date.now() - minutesAgo * 60_000) / STEP) * STEP).toISOString();
const bucket = (minutesAgo: number, over: Record<string, unknown> = {}) => ({ bucketStart: bucketAt(minutesAgo), bpmMin: 62, bpmMax: 91, bpmAvg: 74.5, sampleCount: 5, dataOrigin: "com.example.healthsource", recordingMethod: "automatic", ...over });
const hr = (items: object[], extra: object = {}) => ({ source: "health_connect", heartRate: items, ...extra });
const enable = (token: string, prefs: object = { heartRate: true, restingHeartRate: true, steps: true, sleep: true }) => call("/api/me/device-import/preferences", token, prefs, "PATCH");

test("TEST-01/02 detak jantung: impor valid, replay tidak menggandakan, ringkasan deskriptif", async () => {
  const a = await actor(H);
  await enable(a.token);
  const items = [bucket(90), bucket(85), bucket(80, { bpmMin: 70, bpmMax: 120, bpmAvg: 95, sampleCount: 3 })];
  const first = await J(await call("/api/me/device-import", a.token, hr(items)));
  expect(first.heartRate).toMatchObject({ created: 3, updated: 0, duplicate: 0, rejected: 0 });
  expect(first.simulated).toBe(false);
  const again = await J(await call("/api/me/device-import", a.token, hr(items)));
  expect(again.heartRate).toMatchObject({ created: 0, duplicate: 3 });
  expect(await prisma.wearableHeartRateBucket.count({ where: { userId: a.id } })).toBe(3);

  const summary = await J(await call("/api/me/heart-rate?days=7", a.token));
  expect(summary.series.length).toBe(7);
  expect(summary.latest).toMatchObject({ windowMinutes: 5, simulated: false });
  expect(summary.methodology).toContain("bukan rata-rata berbobot waktu");
  const today = summary.series.at(-1);
  expect(today.sampleCount).toBe(13);
  expect(today.minimum).toBe(62);
  expect(today.maximum).toBe(120);
  expect(summary.series.slice(0, 5).every((d: any) => d.average === null && d.minimum === null && d.restingHeartRate === null)).toBe(true);
  const detail = await J(await call(`/api/me/heart-rate/day?date=${todayWib()}`, a.token));
  expect(detail.buckets.length).toBeGreaterThanOrEqual(3);
  expect(detail.buckets[0]).toHaveProperty("min");
});

test("TEST-03/04 isolasi pengguna dan wajib autentikasi", async () => {
  const a = await actor(H), b = await actor(H);
  await enable(a.token);
  await call("/api/me/device-import", a.token, hr([bucket(60), bucket(55), bucket(50)]));
  expect((await J(await call("/api/me/heart-rate?days=7", b.token))).latest).toBeNull();
  expect(await prisma.wearableHeartRateBucket.count({ where: { userId: b.id } })).toBe(0);
  for (const path of ["/api/me/heart-rate", "/api/me/heart-rate/day?date=2026-11-01", "/api/me/devices/today", "/api/me/device-sync/checkpoints"]) expect((await call(path)).status).toBe(401);
  expect((await call("/api/me/device-import", undefined, hr([bucket(60)]))).status).toBe(401);
});

test("TEST-05/06/16 consent wajib, sakelar jenis data, dan penarikan consent menghentikan impor", async () => {
  const none = await actor([]);
  const denied = await call("/api/me/device-import", none.token, hr([bucket(60)]));
  expect(denied.status).toBe(403);
  expect((await J(denied)).error.code).toBe("CONSENT_REQUIRED");

  const a = await actor(H);
  const off = await J(await call("/api/me/device-import", a.token, hr([bucket(60)], { restingHeartRate: [{ externalId: "r-1", measuredAt: bucketAt(60), bpm: 60 }] })));
  expect(off.heartRate.results[0]).toMatchObject({ status: "REJECTED", reason: "DEVICE_TYPE_DISABLED" });
  expect(off.restingHeartRate.results[0]).toMatchObject({ status: "REJECTED", reason: "DEVICE_TYPE_DISABLED" });
  expect(await prisma.wearableHeartRateBucket.count({ where: { userId: a.id } })).toBe(0);

  await enable(a.token, { heartRate: true });
  expect((await J(await call("/api/me/device-import", a.token, hr([bucket(60)])))).heartRate.created).toBe(1);
  await enable(a.token, { heartRate: false });
  expect((await J(await call("/api/me/device-import", a.token, hr([bucket(120)])))).heartRate.results[0].reason).toBe("DEVICE_TYPE_DISABLED");
  await enable(a.token, { heartRate: true });
  const withdraw = await call("/api/me/consents/withdraw", a.token, { purposes: ["health_data_processing"] });
  expect(withdraw.status).toBeLessThan(500);
  const after = await call("/api/me/device-import", a.token, hr([bucket(130)]));
  expect(after.status).toBe(403);
  expect((await call("/api/me/heart-rate", a.token)).status).toBe(403);
  expect((await call("/api/me/device-sync/checkpoints", a.token, { metric: "heart_rate", outcome: "attempt" }, "PUT")).status).toBe(403);
});

test("TEST-07/08/09/10/11 validasi: nilai teknis ditolak per rekaman, format salah ditolak, batas batch", async () => {
  const a = await actor(H);
  await enable(a.token);
  const mixed = await J(await call("/api/me/device-import", a.token, hr([bucket(70), bucket(65, { bpmMin: 5, bpmAvg: 70 }), bucket(60, { bpmMax: 50, bpmMin: 60 }), bucket(55, { bpmMin: 40, bpmMax: 230, bpmAvg: 90 }), { ...bucket(50), bucketStart: new Date(Math.floor((Date.now() - 50 * 60_000) / STEP) * STEP + 7_000).toISOString() }])));
  expect(mixed.heartRate.results.map((r: any) => r.status)).toEqual(["CREATED", "REJECTED", "REJECTED", "CREATED", "REJECTED"]);
  expect(mixed.heartRate.results.map((r: any) => r.reason)).toEqual([undefined, "HEART_RATE_OUT_OF_DOMAIN", "BUCKET_INCONSISTENT", undefined, "BUCKET_NOT_ALIGNED"]);
  expect(mixed.heartRate.results[3].needsReview).toBe(true);
  expect(mixed.heartRate).toMatchObject({ created: 2, rejected: 3, needsReview: 1 });
  const flagged = await prisma.wearableHeartRateBucket.findFirstOrThrow({ where: { userId: a.id, qualityStatus: "needs_review" } });
  expect(flagged.qualityFlags).toEqual(["UNUSUAL_VALUE"]);

  expect((await call("/api/me/device-import", a.token, hr([{ ...bucket(60), bucketStart: "kemarin" }]))).status).toBe(400);
  expect((await call("/api/me/device-import", a.token, hr([{ ...bucket(60), bucketStart: new Date(Date.now() + 3600_000).toISOString() }]))).status).toBe(400);
  expect((await call("/api/me/device-import", a.token, hr([bucket(60, { dataOrigin: "bukan paket valid!" })]))).status).toBe(400);
  expect((await call("/api/me/device-import", a.token, hr([bucket(60, { bpmAvg: "tujuh puluh" })]))).status).toBe(400);
  expect((await call("/api/me/device-import", a.token, hr([bucket(60, { userId: crypto.randomUUID() })]))).status).toBe(400);
  expect((await call("/api/me/device-import", a.token, { source: "health_connect", heartRate: [] }))).toHaveProperty("status", 400);

  const big = Array.from({ length: 200 }, (_, i) => bucket(1000 + i * 5));
  const ok = await J(await call("/api/me/device-import", a.token, hr(big)));
  expect(ok.heartRate.created).toBe(200);
  expect((await call("/api/me/device-import", a.token, hr([...big, bucket(5)]))).status).toBe(400);
});

test("TEST-12/13/14 checkpoint tidak maju saat gagal, replay aman, koreksi sumber memperbarui bucket dan sesi tidur", async () => {
  const a = await actor(H);
  await enable(a.token);
  const put = (body: object) => call("/api/me/device-sync/checkpoints", a.token, body, "PUT");
  expect((await put({ metric: "heart_rate", outcome: "attempt" })).status).toBe(200);
  const cursor1 = new Date(Date.now() - 3600_000).toISOString();
  expect((await J(await put({ metric: "heart_rate", outcome: "success", cursor: cursor1 }))).cursor).toBe(cursor1);
  const failed = await J(await put({ metric: "heart_rate", outcome: "failure", errorCode: "NETWORK_UNAVAILABLE" }));
  expect(failed).toMatchObject({ cursor: cursor1, lastErrorCode: "NETWORK_UNAVAILABLE" });
  expect(failed.lastSuccessAt).not.toBeNull();
  expect((await put({ metric: "heart_rate", outcome: "failure" })).status).toBe(400);
  expect((await put({ metric: "heart_rate", outcome: "success", errorCode: "X" })).status).toBe(400);
  expect((await put({ metric: "bukan_metrik", outcome: "attempt" })).status).toBe(400);
  const recovered = await J(await put({ metric: "heart_rate", outcome: "success" }));
  expect(recovered.lastErrorCode).toBeNull();
  expect((await J(await call("/api/me/device-sync/checkpoints", a.token))).checkpoints).toHaveLength(1);

  await call("/api/me/device-import", a.token, hr([bucket(40, { sampleCount: 2 })]));
  const richer = await J(await call("/api/me/device-import", a.token, hr([bucket(40, { sampleCount: 5, bpmMax: 99, bpmAvg: 80 })])));
  expect(richer.heartRate).toMatchObject({ updated: 1, created: 0 });
  const stale = await J(await call("/api/me/device-import", a.token, hr([bucket(40, { sampleCount: 1, bpmMax: 70, bpmAvg: 65 })])));
  expect(stale.heartRate).toMatchObject({ unchanged: 1, updated: 0 });
  expect(stale.heartRate.results[0].reason).toBe("OLDER_REVISION");
  const row = await prisma.wearableHeartRateBucket.findFirstOrThrow({ where: { userId: a.id } });
  expect([row.sampleCount, row.bpmMax, row.bpmAvg.toNumber()]).toEqual([5, 99, 80]);
  const dupInRequest = await J(await call("/api/me/device-import", a.token, hr([bucket(35, { sampleCount: 2 }), bucket(35, { sampleCount: 4, bpmAvg: 76 })])));
  expect(dupInRequest.heartRate.results.map((r: any) => r.status)).toEqual(["DUPLICATE", "CREATED"]);
  expect(await prisma.wearableHeartRateBucket.count({ where: { userId: a.id } })).toBe(2);

  const start = new Date(Date.now() - 9 * 3600_000).toISOString(), end = new Date(Date.now() - 2 * 3600_000).toISOString();
  const sleep = (endedAt: string, extra: object = {}) => ({ source: "health_connect", sleep: [{ externalId: "hc-sleep-9", startedAt: start, endedAt, dataOrigin: "com.example.healthsource", ...extra }] });
  expect((await J(await call("/api/me/device-import", a.token, sleep(end)))).sleep.created).toBe(1);
  const finalised = new Date(Date.now() - 1.5 * 3600_000).toISOString();
  const revised = await J(await call("/api/me/device-import", a.token, sleep(finalised)));
  expect(revised.sleep).toMatchObject({ updated: 1, created: 0 });
  const same = await J(await call("/api/me/device-import", a.token, sleep(finalised)));
  expect(same.sleep).toMatchObject({ duplicate: 1, updated: 0 });
  const saved = await prisma.sleepSession.findFirstOrThrow({ where: { userId: a.id } });
  expect(saved.endedAt.toISOString()).toBe(finalised);
  expect(saved.durationMinutes).toBe(Math.round((Date.parse(finalised) - Date.parse(start)) / 60_000));
  expect(await prisma.sleepSession.count({ where: { userId: a.id } })).toBe(1);
});

test("TEST-17 status perangkat: kualitas, kesegaran, dan bendera nilai tidak lazim; Today tidak mengisi nol", async () => {
  const a = await actor(H);
  const before = await J(await call("/api/me/devices/today", a.token));
  expect(before.heartRate.availability).toBe("NOT_ENABLED");
  expect(before.steps.availability).toBe("NOT_ENABLED");

  await enable(a.token);
  const empty = await J(await call("/api/me/devices/today", a.token));
  expect(empty.heartRate).toMatchObject({ availability: "NO_DATA", value: null });
  expect(empty.steps).toMatchObject({ availability: "NO_DATA", value: null });
  expect(empty.sleep.value).toBeNull();

  await call("/api/me/device-import", a.token, hr([bucket(20), bucket(15), bucket(10, { bpmMin: 30, bpmMax: 238, bpmAvg: 100 })], { restingHeartRate: [{ externalId: "rhr-1", measuredAt: bucketAt(20), bpm: 61, dataOrigin: "com.example.healthsource" }] }));
  await call("/api/me/device-sync/checkpoints", a.token, { metric: "heart_rate", outcome: "success" }, "PUT");
  const today = await J(await call("/api/me/devices/today", a.token));
  expect(today.heartRate.availability).toBe("HAS_DATA");
  expect(today.heartRate.value).toMatchObject({ restingBpm: 61, windowMinutes: 5, simulated: false });
  expect(today.steps.value).toBeNull();

  const status = await J(await call("/api/me/devices/status", a.token));
  const hrSignal = status.signals.find((s: any) => s.signal === "heart_rate");
  expect(hrSignal).toMatchObject({ observedDays: 1 });
  expect(status.permissions).toMatchObject({ heartRate: true, restingHeartRate: true });
  expect(status.enabledMetrics).toEqual(expect.arrayContaining(["heartRate", "steps"]));
  expect(status.syncState).toBe("OK");
  expect(status.metricFreshness.find((m: any) => m.metric === "heart_rate").freshness).toBe("FRESH");
  expect(status.metricFreshness.find((m: any) => m.metric === "steps").freshness).toBe("NO_DATA");
  expect(status.days.heart_rate.at(-1).flags).toContain("UNUSUAL_VALUE");
  expect(status.watchVerification).toBe("WATCH_NOT_VERIFIED");
  expect(status.connectionNotice).toContain("tidak membuktikan");
  expect(status).toHaveProperty("signals");
  expect(status).toHaveProperty("notice");

  await call("/api/me/device-sync/checkpoints", a.token, { metric: "steps", outcome: "failure", errorCode: "PERMISSION_REVOKED" }, "PUT");
  const revoked = await J(await call("/api/me/devices/status", a.token));
  expect(revoked).toMatchObject({ syncState: "SYNC_FAILED", permissionState: "PERMISSION_REVOKED" });
  expect((await J(await call("/api/me/devices/today", a.token))).steps.availability).toBe("PERMISSION_REQUIRED");
});

test("TEST-18 proyeksi harian: manual di Health Connect tidak dihitung sebagai bukti perangkat; HR tidak ikut proyeksi", async () => {
  const a = await actor(H);
  await enable(a.token, { workouts: true, steps: true, heartRate: true });
  const date = todayWib();
  const at = new Date(Date.now() - 4 * 3600_000).toISOString();
  const imp = await J(await call("/api/me/activities/import", a.token, { source: "health_connect", sessions: [{ externalId: "w-auto", activityType: "walking", startedAt: at, durationMinutes: 20, recordingMethod: "automatic", device: "watch", dataOrigin: "com.example.healthsource" }, { externalId: "w-manual", activityType: "running", startedAt: new Date(Date.now() - 2 * 3600_000).toISOString(), durationMinutes: 15, recordingMethod: "manual", dataOrigin: "com.example.healthsource" }] }));
  expect(imp.summary.created).toBe(2);
  const facts = (await dailyFacts.list(a.id, date, date)).at(-1)!;
  expect(facts).toMatchObject({ activeMinutes: 35, activeMinutesDevice: 20, activeMinutesManual: 15 });
  await call("/api/me/device-import", a.token, hr([bucket(30), bucket(25), bucket(20)]));
  const after = (await dailyFacts.list(a.id, date, date)).at(-1)!;
  expect(after.activeMinutesDevice).toBe(20);
  expect(Object.keys(after)).not.toContain("heartRate");
  const stored = await prisma.activitySession.findFirstOrThrow({ where: { userId: a.id, externalId: "w-auto" } });
  expect(stored.deviceType).toBe("watch");
  const status = await J(await call("/api/me/devices/status", a.token));
  expect(status.watchVerification).toBe("WATCH_SOURCE_DETECTED");
  expect(status.detectedDeviceTypes).toEqual(["watch"]);
  expect(status.provenance.WATCH_RECORDED).toBeGreaterThanOrEqual(1);
  expect(status.provenance.USER_ENTERED).toBeGreaterThanOrEqual(1);
});

test("TEST-19 data simulasi selalu berlabel, tidak masuk proyeksi/koreksi/ekspor FHIR, dan tidak menaikkan status jam tangan", async () => {
  const a = await actor(H);
  await enable(a.token, { workouts: true, steps: true, sleep: true, heartRate: true, restingHeartRate: true, weight: true, glucose: true });
  const date = todayWib();
  const sim = await J(
    await call("/api/me/device-import", a.token, {
      source: "simulated",
      steps: [{ localDate: date, steps: 9100, dataOrigin: "beokay.simulator" }],
      heartRate: [bucket(30, { device: "watch", dataOrigin: "beokay.simulator" }), bucket(25, { dataOrigin: "beokay.simulator" }), bucket(20, { dataOrigin: "beokay.simulator" })],
      restingHeartRate: [{ externalId: "sim-r-1", measuredAt: bucketAt(30), bpm: 58, device: "watch", dataOrigin: "beokay.simulator" }],
      sleep: [{ externalId: "sim-s-1", startedAt: new Date(Date.now() - 9 * 3600_000).toISOString(), endedAt: new Date(Date.now() - 2 * 3600_000).toISOString(), device: "watch", dataOrigin: "beokay.simulator" }],
      weights: [{ externalId: "sim-w", measuredAt: new Date(Date.now() - 3600_000).toISOString(), kg: 70 }],
      glucose: [{ externalId: "sim-g", measuredAt: new Date(Date.now() - 3600_000).toISOString(), value: 100, unit: "mg/dL" }],
    }),
  );
  expect(sim.simulated).toBe(true);
  expect(sim.heartRate.created).toBe(3);
  expect(sim.weights.results[0]).toMatchObject({ status: "REJECTED", reason: "SIMULATED_NOT_SUPPORTED" });
  expect(sim.glucose.results[0]).toMatchObject({ status: "REJECTED", reason: "SIMULATED_NOT_SUPPORTED" });
  expect(await prisma.glucoseObservation.count({ where: { userId: a.id } })).toBe(0);
  expect(await prisma.vitalMeasurement.count({ where: { userId: a.id } })).toBe(0);
  expect(await prisma.wearableHeartRateBucket.count({ where: { userId: a.id, source: "simulated" } })).toBe(3);
  const act = await J(await call("/api/me/activities/import", a.token, { source: "simulated", sessions: [{ externalId: "sim-w-1", activityType: "walking", startedAt: new Date(Date.now() - 5 * 3600_000).toISOString(), durationMinutes: 30, device: "watch" }] }));
  expect(act.summary.created).toBe(1);

  const steps = await J(await call("/api/me/steps?days=7", a.token));
  expect(steps.series.at(-1)).toMatchObject({ steps: 9100, simulated: true });
  expect((await J(await call("/api/me/heart-rate?days=7", a.token))).simulated).toBe(true);
  const today = await J(await call("/api/me/devices/today", a.token));
  expect(today.steps.value.simulated).toBe(true);
  expect(today.heartRate.value.simulated).toBe(true);
  const status = await J(await call("/api/me/devices/status", a.token));
  expect(status).toMatchObject({ simulated: true, watchVerification: "WATCH_NOT_VERIFIED" });
  expect(status.provenance.SIMULATED).toBeGreaterThan(0);
  expect(status.provenance.WATCH_RECORDED).toBe(0);
  expect(status.detectedDeviceTypes).toEqual([]);

  const facts = (await dailyFacts.list(a.id, date, date)).at(-1)!;
  expect(facts).toMatchObject({ steps: null, sleepMinutes: null, activeMinutes: 0, sessionCount: 0 });
  const fhir = await call("/api/me/export/fhir", a.token);
  if (fhir.status === 200) expect(JSON.stringify(await fhir.json())).not.toContain("9100");

  const bundle = await J(await call("/api/me/export", a.token));
  expect(bundle.counts).toMatchObject({ wearableHeartRateBuckets: 3, wearableRestingHeartRates: 1 });
});

test("TEST-20 produksi menolak operasi simulasi di server, bukan hanya di UI", async () => {
  const a = await actor(H);
  await enable(a.token, { steps: true, heartRate: true });
  const body = { source: "simulated" as const, steps: [{ localDate: todayWib(), steps: 100 }], weights: [], glucose: [], sleep: [], heartRate: [], restingHeartRate: [] };
  const input = body as Parameters<typeof deviceImportService.import>[1];
  await expect(deviceImportService.import(a.id, input, new Date(), { simulationAllowed: false })).rejects.toMatchObject({ status: 403, code: "SIMULATION_DISABLED" });
  expect(await prisma.dailySteps.count({ where: { userId: a.id } })).toBe(0);
  const live = await deviceImportService.import(a.id, input, new Date(), { simulationAllowed: true });
  expect(live.simulated).toBe(true);
  expect(await prisma.dailySteps.count({ where: { userId: a.id, source: "simulated" } })).toBe(1);
  const { activityImportService } = await import("../../src/features/activity/activity-import.service.ts");
  await expect(activityImportService.import(a.id, "simulated", [{ externalId: "x", activityType: "walking", startedAt: new Date(Date.now() - 3600_000).toISOString(), durationMinutes: 10 }], new Date(), { simulationAllowed: false })).rejects.toMatchObject({ status: 403, code: "SIMULATION_DISABLED" });
  expect((await call("/api/me/device-import", a.token, { source: "tidak_dikenal", steps: [{ localDate: todayWib(), steps: 1 }] })).status).toBe(400);
});

test("kompatibilitas: klien lama tanpa bidang baru tetap dilayani, ekspor memuat tabel baru, penghapusan akun membersihkan", async () => {
  const a = await actor(H);
  await enable(a.token);
  const legacy = await J(await call("/api/me/device-import", a.token, { source: "health_connect", steps: [{ localDate: todayWib(), steps: 4000 }], sleep: [{ externalId: "legacy-s", startedAt: new Date(Date.now() - 8 * 3600_000).toISOString(), endedAt: new Date(Date.now() - 3600_000).toISOString() }] }));
  expect(legacy.steps).toMatchObject({ upserted: 1 });
  expect(legacy.sleep).toMatchObject({ created: 1 });
  expect(legacy.heartRate).toMatchObject({ created: 0, rejected: 0 });
  expect(await J(await call("/api/me/device-import/preferences", a.token))).toMatchObject({ heartRate: true, restingHeartRate: true, weight: false });
  await call("/api/me/device-import", a.token, hr([bucket(30), bucket(25), bucket(20)]));
  await call("/api/me/device-sync/checkpoints", a.token, { metric: "steps", outcome: "success" }, "PUT");
  const bundle = await J(await call("/api/me/export", a.token));
  expect(bundle.counts).toMatchObject({ wearableHeartRateBuckets: 3, deviceSyncCheckpoints: 1 });
  await prisma.users.delete({ where: { id: a.id } });
  expect(await prisma.wearableHeartRateBucket.count({ where: { userId: a.id } })).toBe(0);
  expect(await prisma.deviceSyncCheckpoint.count({ where: { userId: a.id } })).toBe(0);
});
