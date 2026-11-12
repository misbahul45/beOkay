import { afterAll, beforeAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { retentionService } from "../../src/features/retention/retention.service.ts";
import { J, actors, call, hash, requireIsolatedApi, todayWib, wib } from "../support/api.ts";

const { actor, cleanup } = actors();
const H = ["health_data_processing", "descriptive_summaries"];
const mail = process.env.MAILPIT_API_URL;

beforeAll(requireIsolatedApi);
afterAll(async () => {
  await prisma.featureFlag.deleteMany({});
  await cleanup();
});

const glucose = (token: string, value: number, measuredAt: Date, mealContext = "fasting", id = crypto.randomUUID()) =>
  call("/api/me/glucose", token, { id, originalValue: value, originalUnit: "mg/dL", measuredAt: measuredAt.toISOString(), mealContext });

test("D-1 analitik: tanpa consent tidak ada baris; dengan consent peristiwa server dan klien tercatat tanpa isi; tarik consent menghapus", async () => {
  const a = await actor(H);
  const now = new Date().toISOString();
  const batch = { platform: "android", appVersion: "1.0.0+1", events: [{ type: "form_saved", domain: "glucose", meta: { via: "form", durationMs: 5000 }, occurredAt: now }] };
  expect(await J(await call("/api/me/usage-events", a.token, batch))).toEqual({ accepted: 0, dropped: 1, recorded: false });
  await glucose(a.token, 110, new Date(Date.now() - 60_000));
  expect(await prisma.usageEvent.count({ where: { userId: a.id } })).toBe(0);

  const policy = await J(await call("/api/consent-policies/current"));
  await call("/api/me/consents", a.token, { policyVersion: policy.version, purposes: ["product_analytics"] });
  expect((await call("/api/me/usage-events", a.token, { events: [{ type: "form_saved", meta: { note: "gula 250" }, occurredAt: now }] })).status).toBe(400);
  expect(await J(await call("/api/me/usage-events", a.token, batch))).toEqual({ accepted: 1, dropped: 0, recorded: true });
  const id = crypto.randomUUID();
  await glucose(a.token, 112, new Date(Date.now() - 30_000), "fasting", id);
  await glucose(a.token, 112, new Date(Date.now() - 30_000), "fasting", id);
  const rows = await prisma.usageEvent.findMany({ where: { userId: a.id }, orderBy: { occurredAt: "asc" } });
  expect(rows.map((r) => [r.eventType, r.domain, r.platform])).toEqual([["form_saved", "glucose", "android"], ["record_created", "glucose", "server"]]);
  expect(JSON.stringify(rows)).not.toMatch(/112|110|mg\/dL/);
  const mine = await J(await call("/api/me/usage-events", a.token));
  expect(mine).toMatchObject({ recording: true, count: 2, byType: { form_saved: 1, record_created: 1 } });

  await call("/api/me/consents/withdraw", a.token, { purposes: ["product_analytics"] });
  expect(await prisma.usageEvent.count({ where: { userId: a.id } })).toBe(0);
  await glucose(a.token, 115, new Date(Date.now() - 10_000));
  expect(await prisma.usageEvent.count({ where: { userId: a.id } })).toBe(0);
});

test("K-2 jangkar klinis: catat, idempoten, batas, koreksi dengan revisi, ringkasan deskriptif, batas kepemilikan, ekspor", async () => {
  const a = await actor(H), b = await actor(H);
  expect((await call("/api/me/vitals", (await actor(["health_data_processing"])).token)).status).toBe(200);
  expect((await call("/api/me/vitals", (await actor([])).token)).status).toBe(403);
  const w1 = { id: crypto.randomUUID(), kind: "weight", value: 74.5, unit: "kg", measuredAt: new Date(Date.now() - 20 * 86_400_000).toISOString() };
  const w2 = { id: crypto.randomUUID(), kind: "weight", value: 72, unit: "kg", measuredAt: new Date(Date.now() - 86_400_000).toISOString() };
  expect((await call("/api/me/vitals", a.token, w1)).status).toBe(201);
  expect((await call("/api/me/vitals", a.token, w1)).status).toBe(201);
  expect((await call("/api/me/vitals", a.token, { ...w1, value: 80 })).status).toBe(409);
  const saved = await J(await call("/api/me/vitals", a.token, w2));
  expect(saved).toMatchObject({ kind: "weight", value: 72, unit: "kg", display: "72 kg", version: 1 });
  expect((await call("/api/me/vitals", a.token, { id: crypto.randomUUID(), kind: "weight", value: 160, unit: "cm", measuredAt: w2.measuredAt })).status).toBe(422);
  expect((await call("/api/me/vitals", a.token, { id: crypto.randomUUID(), kind: "blood_pressure", value: 80, value2: 120, unit: "mmHg", measuredAt: w2.measuredAt })).status).toBe(422);
  expect((await call("/api/me/vitals", a.token, { id: crypto.randomUUID(), kind: "blood_pressure", value: 128, value2: 82, unit: "mmHg", measuredAt: w2.measuredAt })).status).toBe(201);
  expect((await call(`/api/me/vitals/${saved.id}`, b.token)).status).toBe(404);
  expect((await call(`/api/me/vitals/${saved.id}`, b.token, { expectedVersion: 1, reason: "x", value: 1 }, "PATCH")).status).toBe(404);
  const fixed = await J(await call(`/api/me/vitals/${saved.id}`, a.token, { expectedVersion: 1, reason: "Salah ketik", value: 72.4 }, "PATCH"));
  expect(fixed).toMatchObject({ value: 72.4, version: 2 });
  expect((await call(`/api/me/vitals/${saved.id}`, a.token, { expectedVersion: 1, reason: "lagi", value: 72 }, "PATCH")).status).toBe(409);
  expect((await J(await call(`/api/me/vitals/${saved.id}/revisions`, a.token))).items).toHaveLength(1);

  const lab = { id: crypto.randomUUID(), test: "hba1c", value: 7.4, unit: "%", sampledAt: new Date(Date.now() - 100 * 86_400_000).toISOString().slice(0, 10), labName: "Lab Contoh", source: "lab_report" };
  expect((await call("/api/me/labs", a.token, lab)).status).toBe(201);
  expect((await call("/api/me/labs", a.token, { ...lab, id: crypto.randomUUID(), unit: "mg/dL" })).status).toBe(422);
  const s = await J(await call("/api/me/clinical/summary", a.token));
  const weight = s.vitals.find((v: any) => v.kind === "weight");
  expect(weight).toMatchObject({ latest: { value: 72.4 }, previous: { value: 74.5 }, change: { difference: -2.1, direction: "DOWN" } });
  expect(s.vitals.find((v: any) => v.kind === "blood_pressure").latest.display).toBe("128/82 mmHg");
  expect(s.hba1c).toMatchObject({ status: "DUE", lastSampledAt: lab.sampledAt });
  expect(JSON.stringify(s)).not.toMatch(/obesitas|normal|hipertensi|buruk|baik/i);
  expect((await J(await call("/api/me/clinical/summary", b.token))).hba1c.status).toBe("NONE");

  const bundle = await J(await call("/api/me/export", a.token));
  expect(bundle.counts).toMatchObject({ vitalMeasurements: 3, labResults: 1 });
  expect(bundle.data.vitalMeasurements[0].createHash).toBeUndefined();
});

test("K-2 pengingat HbA1c: satu notifikasi per hasil yang sudah 90 hari, tidak berulang", async () => {
  const a = await actor(H);
  const { clinicalService } = await import("../../src/features/clinical/clinical.service.ts");
  await prisma.labResult.create({ data: { userId: a.id, test: "hba1c", value: 7, unit: "%", sampledAt: new Date(Date.now() - 95 * 86_400_000), createHash: hash() } });
  await clinicalService.remindDueLabs();
  await clinicalService.remindDueLabs();
  const n = await prisma.notification.findMany({ where: { userId: a.id, kind: "LAB_REMINDER" } });
  expect(n).toHaveLength(1);
  expect(n[0]).toMatchObject({ action: "OPEN_CLINICAL" });
});

test("U-1 catat cepat: makan dan aktivitas berulang jadi templat satu ketukan; templat tersimpan lewat API yang sama", async () => {
  const a = await actor(H), b = await actor(H);
  const food = await J(await call("/api/me/foods", a.token, { name: "Nasi uduk", source: "Label kemasan", status: "user_reported", per100g: { calories: 180, carbohydrates: 30, protein: 4, fat: 5, fiber: 1 } }));
  for (let i = 1; i <= 3; i++) {
    expect((await call("/api/me/meals", a.token, { id: crypto.randomUUID(), category: "breakfast", consumedAt: new Date(Date.now() - i * 86_400_000).toISOString(), items: [{ foodId: food.id, name: "Nasi uduk", quantity: 1, unit: "portion", grams: 150, gramsBasis: "user_estimate" }, { name: "Teh manis", quantity: 1, unit: "piece" }] })).status).toBe(201);
  }
  await call("/api/me/meals", a.token, { id: crypto.randomUUID(), category: "lunch", consumedAt: new Date(Date.now() - 2 * 86_400_000).toISOString(), items: [{ name: "Gado-gado", quantity: 1, unit: "portion" }] });
  for (let i = 1; i <= 2; i++) await call("/api/me/activities", a.token, { id: crypto.randomUUID(), activityType: "walking", startedAt: new Date(Date.now() - i * 86_400_000 - 3600_000).toISOString(), durationMinutes: 20, reportedIntensity: "light" });
  const s = await J(await call("/api/me/quick-record/suggestions", a.token));
  expect(s.meals[0]).toMatchObject({ title: "Nasi uduk, Teh manis", category: "breakfast", count: 3, nutritionKnown: false });
  expect(s.meals[1]).toMatchObject({ title: "Gado-gado", count: 1 });
  expect(s.activities[0]).toMatchObject({ title: "Jalan kaki 20 menit", count: 2, template: { activityType: "walking", durationMinutes: 20, reportedIntensity: "light" } });
  expect((await J(await call("/api/me/quick-record/suggestions", b.token))).meals).toEqual([]);
  const repeat = await call("/api/me/meals", a.token, { id: crypto.randomUUID(), consumedAt: new Date().toISOString(), ...s.meals[0].template });
  expect(repeat.status).toBe(201);
  const meal = await J(repeat);
  expect(meal.items.find((i: any) => i.name === "Nasi uduk").nutrition.calories).toBe(270);
  expect((await call("/api/me/activities", a.token, { id: crypto.randomUUID(), startedAt: new Date(Date.now() - 30 * 60_000).toISOString(), ...s.activities[0].template })).status).toBe(201);
});

test("U-5, U-6, K-10: konteks pribadi setelah simpan, pasangan glukosa sekitar makan, pesan nilai ekstrem", async () => {
  const a = await actor(H);
  for (const [d, v] of [[2, 130], [3, 126], [5, 128]] as const) await glucose(a.token, v, new Date(Date.now() - d * 86_400_000));
  const id = crypto.randomUUID();
  const rec = await J(await glucose(a.token, 110, new Date(Date.now() - 60_000), "fasting", id));
  expect(rec.alert).toBeNull();
  const ctx = await J(await call(`/api/me/glucose/${id}/context`, a.token));
  expect(ctx).toMatchObject({ comparison: { median: 128, n: 3, comparison: "LOWER", basis: "SAME_CONTEXT" }, line: "Lebih rendah dari median puasa 14 harimu: 128 mg/dL dari 3 catatan.", previous: { value: 130 } });
  const lowId = crypto.randomUUID();
  const low = await J(await glucose(a.token, 55, new Date(Date.now() - 30_000), "other", lowId));
  expect(low.alert).toMatchObject({ level: "LOW", thresholdMgDl: 70 });
  expect((await J(await call(`/api/me/glucose/${lowId}/context`, a.token))).alert.level).toBe("LOW");
  expect((await J(await glucose(a.token, 320, new Date(Date.now() - 20_000), "other"))).alert.level).toBe("HIGH");
  const other = await actor(H);
  expect((await call(`/api/me/glucose/${id}/context`, other.token)).status).toBe(404);
  expect((await call(`/api/me/glucose/${id}/context`, (await actor(["health_data_processing"])).token)).status).toBe(403);

  const mealAt = new Date(Date.now() - 4 * 3600_000);
  const mealId = crypto.randomUUID();
  await call("/api/me/meals", a.token, { id: mealId, category: "lunch", consumedAt: mealAt.toISOString(), items: [{ name: "Nasi", quantity: 1, unit: "portion" }] });
  await glucose(a.token, 105, new Date(mealAt.getTime() - 15 * 60_000), "before_meal");
  await glucose(a.token, 162, new Date(mealAt.getTime() + 118 * 60_000), "after_meal");
  const mc = await J(await call(`/api/me/meals/${mealId}/context`, a.token));
  expect(mc.glucosePair).toMatchObject({ before: { value: 105, minutesFromMeal: -15 }, after: { value: 162, minutesFromMeal: 118 }, difference: 57 });
  expect(mc.glucosePair.note).toContain("bukan sebab-akibat");
  expect(mc.carbLine).toContain("belum lengkap");
});

test("S-2 sakelar fitur: mematikan komunitas dan Asisten berlaku tanpa restart, fitur lain tetap jalan, perubahan diaudit", async () => {
  const a = await actor(H);
  const { featureFlags } = await import("../../src/features/feature-flags/feature-flags.service.ts");
  expect((await J(await call("/api/me/features", a.token))).features.community).toBe(true);
  await featureFlags.set("community", false, "test-suite", "uji kill-switch");
  await featureFlags.set("conversation", false, "test-suite", null);
  const blocked = await call("/api/me/community/overview", a.token);
  expect(blocked.status).toBe(503);
  expect((await J(blocked)).error).toMatchObject({ code: "FEATURE_DISABLED", details: { feature: "community" } });
  expect((await call(`/api/me/conversations/${crypto.randomUUID()}/messages`, a.token, { clientMessageId: crypto.randomUUID(), text: "halo" })).status).toBe(503);
  expect((await call("/api/me/glucose", a.token)).status).toBe(200);
  expect((await J(await call("/api/me/features", a.token))).features).toMatchObject({ community: false, conversation: false, assistant: true });
  await featureFlags.clear("community", "test-suite");
  await featureFlags.clear("conversation", "test-suite");
  expect((await call("/api/me/community/overview", a.token)).status).toBe(200);
  const audit = await prisma.auditEvent.findMany({ where: { eventType: "feature_flag_changed", userId: null }, orderBy: { occurredAt: "desc" }, take: 4 });
  expect(audit.map((x) => (x.metadata as any).key).sort()).toEqual(["community", "community", "conversation", "conversation"]);
});

test("D-5 laporan kejadian: tersimpan, diaudit, dikirim ke surel pemilik, dibatasi laju, ikut ekspor", async () => {
  if (!mail) throw new Error("Mailpit required");
  const a = await actor(H);
  expect((await call("/api/me/reports", a.token, { category: "bug", message: "x" })).status).toBe(400);
  const r = await J(await call("/api/me/reports", a.token, { category: "adverse_event", message: "Setelah mengikuti rencana jalan kaki saya pusing.", contactOk: true, appVersion: "1.0.0+1" }));
  expect(r).toMatchObject({ category: "adverse_event", emailed: true });
  expect(r.message).toContain("119");
  const listing = (await (await fetch(`${mail}/api/v1/messages`)).json()) as { messages: { Subject: string; To: { Address: string }[] }[] };
  expect(listing.messages.some((m) => m.To.some((t) => t.Address === "owner@beokay.test") && m.Subject.includes("KEJADIAN"))).toBe(true);
  expect(await prisma.auditEvent.count({ where: { userId: a.id, eventType: "incident_reported" } })).toBe(1);
  for (let i = 0; i < 4; i++) await call("/api/me/reports", a.token, { category: "other", message: `catatan ${i} untuk uji` });
  expect((await call("/api/me/reports", a.token, { category: "other", message: "keenam kalinya" })).status).toBe(429);
  expect((await J(await call("/api/me/reports", a.token))).items).toHaveLength(5);
  expect((await J(await call("/api/me/export", a.token))).counts.incidentReports).toBe(5);
});

test("S-3 retensi: hanya data lewat batas yang dihapus; data baru dan notifikasi belum dibaca tetap", async () => {
  const a = await actor(H);
  const old = new Date(Date.now() - 500 * 86_400_000);
  await prisma.auditEvent.create({ data: { userId: a.id, eventType: "retention_probe_old", occurredAt: old } });
  await prisma.auditEvent.create({ data: { userId: a.id, eventType: "retention_probe_new" } });
  await prisma.notification.create({ data: { userId: a.id, kind: "REMINDER", title: "lama dibaca", body: "x", action: "OPEN_LOG", dedupeKey: "r-old-read", createdAt: old, readAt: old } });
  await prisma.notification.create({ data: { userId: a.id, kind: "REMINDER", title: "lama belum dibaca", body: "x", action: "OPEN_LOG", dedupeKey: "r-old-unread", createdAt: old } });
  await prisma.usageEvent.create({ data: { userId: a.id, eventType: "screen_opened", occurredAt: old } });
  const dry = await retentionService.run(undefined, new Date(), { dryRun: true });
  expect(dry.dryRun).toBe(true);
  expect(await prisma.auditEvent.count({ where: { userId: a.id, eventType: "retention_probe_old" } })).toBe(1);
  const r = await retentionService.run();
  expect(r.deleted!.auditEvents).toBeGreaterThanOrEqual(1);
  expect(await prisma.auditEvent.findMany({ where: { userId: a.id, eventType: { startsWith: "retention_probe" } }, select: { eventType: true } })).toEqual([{ eventType: "retention_probe_new" }]);
  expect((await prisma.notification.findMany({ where: { userId: a.id }, select: { dedupeKey: true } })).map((n) => n.dedupeKey)).toEqual(["r-old-unread"]);
  expect(await prisma.usageEvent.count({ where: { userId: a.id } })).toBe(0);
  expect(await prisma.auditEvent.count({ where: { eventType: "retention_applied" } })).toBeGreaterThanOrEqual(1);
});

test("Sinkron luring menerima domain vital dan lab", async () => {
  const a = await actor(H);
  const recordId = crypto.randomUUID();
  const res = await J(await call("/api/me/sync/operations", a.token, { operations: [{ operationId: crypto.randomUUID(), domain: "vital", recordId, operationType: "create", payload: { kind: "waist", value: 92, unit: "cm", measuredAt: new Date(Date.now() - 60_000).toISOString() } }] }));
  expect(res.items[0]).toMatchObject({ status: "SYNCED", recordId });
  expect(await prisma.vitalMeasurement.count({ where: { userId: a.id, kind: "waist" } })).toBe(1);
  void todayWib;
  void wib;
});

test("Ukuran Fase 8 dapat dihitung dari DB hanya untuk kohort ber-consent analitik", async () => {
  const { measuresService } = await import("../../src/features/usage/measures.service.ts");
  const a = await actor([...H, "product_analytics"]);
  await call("/api/me/usage-events", a.token, { events: [{ type: "quick_repeat_used", domain: "meal", occurredAt: new Date().toISOString() }, { type: "context_viewed", domain: "glucose", occurredAt: new Date().toISOString() }] });
  await glucose(a.token, 120, new Date(Date.now() - 60_000));
  const m = await measuresService.compute({ from: new Date(Date.now() - 7 * 86_400_000), to: new Date(Date.now() + 60_000) });
  expect(m.cohort.users).toBeGreaterThanOrEqual(1);
  expect(m.quickRecord.quickRepeats).toBeGreaterThanOrEqual(1);
  expect(m.quickRecord.recordsCreated).toBeGreaterThanOrEqual(1);
  expect(m.feedbackAtSave.userDaysWithContextView).toBeGreaterThanOrEqual(1);
  expect(Object.keys(m)).toEqual(expect.arrayContaining(["engagement", "mealGlucosePairs", "clinicalAnchors", "adaptiveGoals", "problemSolving", "safetyReports", "operations"]));
});
