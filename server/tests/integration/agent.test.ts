import { afterAll, beforeAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { ToolError, executeTool, type ToolContext } from "../../src/features/agent/agent.tools.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
const J = async (r: Response) => (await r.json()) as any;
async function actor(purposes: string[] = ["health_data_processing", "personalized_ai"]) {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "Fixture", email: `ag-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  const policy = (await (await call("/api/consent-policies/current", token)).json()) as any;
  await call("/api/me/consents", token, { policyVersion: policy.version, purposes });
  await call("/api/me/preferences", token, { timezone: "Asia/Jakarta" }, "PATCH");
  return { id, token };
}
const key = () => `k-${crypto.randomUUID()}`;
const run = (token: string, message: string, query?: string, idempotencyKey = key()) => call("/api/me/agent/runs", token, { idempotencyKey, message, ...(query ? { query } : {}) });
const decide = (token: string, recId: string, decision: "ACCEPT" | "REJECT", expectedVersion = 1, operationId: string = crypto.randomUUID()) => call(`/api/me/agent/recommendations/${recId}/decision`, token, { operationId, decision, expectedVersion });

// Fixture referensi: kata unik "zeltuk" agar tidak bertabrakan dengan data TKPI asli di DB uji.
const food = [
  ["ZZAG01", "Zeltuk tempe goreng", 300, 12, 20, 18],
  ["ZZAG02", "Zeltuk tahu kukus", 80, 2, 8, 5],
  ["ZZAG03", "Zeltuk kacang rebus", 320, 20, 25, 14],
  ["ZZAG04", "Zeltuk bayam tumis", 40, 4, 3, 2],
  ["ZZAG05", "Zeltuk ikan pepes", 150, 1, 20, 7],
] as const;
beforeAll(async () => {
  for (const [code, name, cal, carb, protein, fat] of food)
    await prisma.$executeRawUnsafe(`INSERT INTO food_reference (code,name,name_normalized,source,source_version,source_ref,page,chapter,status,calories,carbohydrates,protein,fat,updated_at) VALUES ('${code}','${name}','${name.toLowerCase()}','Tabel Komposisi Pangan Indonesia','TKPI 2017','KZGMI-2001',30,'4.1. UJI','verified_auto',${cal},${carb},${protein},${fat},now())`);
});
afterAll(async () => {
  await prisma.$executeRawUnsafe(`DELETE FROM food_reference WHERE code LIKE 'ZZAG%'`);
  await prisma.users.deleteMany({ where: { id: { in: users } } });
});
const names = (r: any) => r.recommendations.map((x: any) => x.candidate.name);

test("Akses: butuh login, dan consent personalized_ai + kesehatan; daftar alat deny-by-default", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  expect((await call("/api/me/agent/runs", undefined, { idempotencyKey: key(), message: "alternatif zeltuk" })).status).toBe(401);
  const noAi = await actor(["health_data_processing"]);
  expect((await run(noAi.token, "alternatif zeltuk")).status).toBe(403);
  const ok = await actor();
  const tools = await J(await call("/api/me/agent/tools", ok.token));
  expect(tools.items.map((t: any) => t.name).sort()).toEqual(["get_activity_context", "get_behavior_goals", "get_food_preferences", "get_personalization", "search_food_reference", "search_user_foods", "search_web_nutrition"]);
  expect(JSON.stringify(tools)).not.toMatch(/sql|shell|fetch_url/i);
});

test("Permintaan berisiko diblokir SEBELUM alat apa pun berjalan; tidak ada saran dan tidak ada data berubah", async () => {
  const a = await actor();
  for (const [msg, code] of [["naikkan dosis metformin saya", "MEDICATION_ADVICE"], ["apakah saya terkena diabetes?", "DIAGNOSIS_REQUEST"], ["saya pingsan, makan apa?", "URGENT_SYMPTOM"]] as const) {
    const r = await J(await run(a.token, msg));
    expect(r).toMatchObject({ status: "BLOCKED", safetyDecision: code });
    expect(r.recommendations).toEqual([]);
    expect(r.message).toBeTruthy();
    expect(await prisma.agentToolCall.count({ where: { runId: r.id } })).toBe(0);
  }
  expect(await prisma.recommendation.count({ where: { userId: a.id } })).toBe(0);
});

test("Alur penuh: usulan bersumber, kendala keras, tidak ada tulisan domain sebelum setuju, persetujuan tepat sekali", async () => {
  const a = await actor();
  await call("/api/me/food-preferences", a.token, { kind: "allergy", term: "kacang" });
  const mealsBefore = await prisma.mealLog.count({ where: { userId: a.id } });
  const r = await J(await run(a.token, "carikan alternatif zeltuk", "zeltuk"));
  expect(r.status).toBe("WAITING_FOR_USER");
  expect(r.safetyDecision).toBe("NEEDS_USER_CONFIRMATION");
  expect(r.recommendations.length).toBeGreaterThan(0);
  expect(r.recommendations.length).toBeLessThanOrEqual(3);
  expect(names(r)).not.toContain("Zeltuk kacang rebus"); // alergi: dikecualikan sebelum peringkat
  expect(r.summary.excludedByConstraints).toBeGreaterThanOrEqual(1);
  for (const rec of r.recommendations) {
    expect(rec).toMatchObject({ type: "NUTRITION", status: "OFFERED", version: 1, requiresConfirmation: true, policyVersion: "safety-policy-v1" });
    expect(rec.evidenceRefs[0]).toMatchObject({ kind: "TKPI", sourceRef: "KZGMI-2001" });
    expect(rec.limitations.join(" ")).toContain("Alergi hanya dicek dari nama");
    expect(rec.candidate.per100g.fiber).toBeNull(); // nilai yang tidak ada tidak dikarang
    expect(JSON.stringify(rec)).not.toMatch(/menurunkan gula|menyembuhkan|dosis/i);
  }
  expect(r.events.map((e: any) => e.type)).toEqual(expect.arrayContaining(["SAFETY_SCREEN", "CANDIDATES_RETRIEVED", "FILTERED", "RANKED", "RECOMMENDATIONS_OFFERED"]));
  expect(await prisma.agentToolCall.count({ where: { runId: r.id, status: "OK" } })).toBe(4);
  // Menawarkan tidak menulis apa pun di domain.
  expect(await prisma.plannedMeal.count({ where: { userId: a.id } })).toBe(0);
  expect(await prisma.mealLog.count({ where: { userId: a.id } })).toBe(mealsBefore);

  const rec = r.recommendations[0];
  const op = crypto.randomUUID();
  const first = await J(await decide(a.token, rec.id, "ACCEPT", rec.version, op));
  expect(first).toMatchObject({ replayed: false, recommendation: { status: "ACCEPTED", version: 2 } });
  expect(first.plannedMealId).toBeTruthy();
  // Ulang dengan operationId sama (klien mencoba lagi): balasan tersimpan, tidak ada baris baru.
  const again = await J(await decide(a.token, rec.id, "ACCEPT", rec.version, op));
  expect(again).toMatchObject({ replayed: true, plannedMealId: first.plannedMealId });
  // operationId baru pada saran yang sudah diputuskan ditolak.
  expect((await decide(a.token, rec.id, "ACCEPT", 2)).status).toBe(409);
  // operationId yang sama untuk keputusan berbeda ditolak.
  expect((await decide(a.token, rec.id, "REJECT", rec.version, op)).status).toBe(409);
  expect(await prisma.plannedMeal.count({ where: { userId: a.id } })).toBe(1);
  // Rencana BUKAN konsumsi.
  expect(await prisma.mealLog.count({ where: { userId: a.id } })).toBe(mealsBefore);
  const plans = await J(await call("/api/me/planned-meals", a.token));
  expect(plans.items[0]).toMatchObject({ status: "PLANNED", name: rec.candidate.name });
});

test("Persetujuan bersamaan dengan operationId sama: tepat satu rencana dan tidak ada duplikasi", async () => {
  const a = await actor();
  const r = await J(await run(a.token, "alternatif zeltuk", "zeltuk"));
  const rec = r.recommendations[0];
  const op = crypto.randomUUID();
  const results = await Promise.all([decide(a.token, rec.id, "ACCEPT", 1, op), decide(a.token, rec.id, "ACCEPT", 1, op), decide(a.token, rec.id, "ACCEPT", 1, op)]);
  expect(results.map((x) => x.status).every((s) => s === 200 || s === 409)).toBe(true);
  expect(results.some((x) => x.status === 200)).toBe(true);
  expect(await prisma.plannedMeal.count({ where: { userId: a.id } })).toBe(1);
  expect(await prisma.recommendationDecision.count({ where: { userId: a.id } })).toBe(1);
  // Yang kena 409 sementara mendapat balasan tersimpan saat mengulang.
  const retry = await J(await decide(a.token, rec.id, "ACCEPT", 1, op));
  expect(retry.replayed).toBe(true);
});

test("Lingkar umpan balik: penolakan menyimpan umpan balik, menaikkan versi personalisasi, dan mengubah peringkat berikutnya", async () => {
  const a = await actor();
  const first = await J(await run(a.token, "alternatif zeltuk", "zeltuk"));
  const top = first.recommendations[0];
  const topName: string = top.candidate.name;
  expect(top.personalization.penalty).toBe(0);
  expect((await J(await call("/api/me/personalization", a.token))).version).toBe(0);

  const rejected = await J(await decide(a.token, top.id, "REJECT", top.version));
  expect(rejected.recommendation.status).toBe("REJECTED");
  expect(rejected.personalizationVersion).toBe(1);
  expect(await prisma.plannedMeal.count({ where: { userId: a.id } })).toBe(0); // menolak tidak menulis rencana
  const prof = await J(await call("/api/me/personalization", a.token));
  expect(prof).toMatchObject({ version: 1, method: "DETERMINISTIC_RULES", rulesVersion: "pref-rules-v2" });
  expect(prof.dislikedTerms.length).toBeGreaterThan(0);
  const ev = await prisma.personalizationEvent.findFirstOrThrow({ where: { userId: a.id, version: 1 } });
  expect(ev).toMatchObject({ reason: "RECOMMENDATION_REJECTED", sourceRecommendationId: top.id });

  // Permintaan baru: butir yang ditolak turun peringkat, dengan alasan yang dapat dijelaskan.
  const second = await J(await run(a.token, "alternatif zeltuk lagi", "zeltuk"));
  expect(second.summary.profileVersion).toBe(1);
  const before = names(first), after = names(second);
  const sameItem = second.recommendations.find((x: any) => x.candidate.name === topName);
  if (sameItem) {
    expect(after.indexOf(topName)).toBeGreaterThan(0); // tidak lagi di puncak
    expect(sameItem.personalization.penalty).toBeGreaterThan(0);
    expect(sameItem.personalization.matchedTerms.length).toBeGreaterThan(0);
    expect(sameItem.explanation).toContain("pernah menolak");
  }
  expect(after[0]).not.toBe(before[0]);

  // Pengguna dapat menghapus hasil pembelajaran; versi tetap naik (riwayat dapat diaudit).
  const reset = await J(await call("/api/me/personalization", a.token, undefined, "DELETE"));
  expect(reset.version).toBe(2);
  expect((await J(await call("/api/me/personalization", a.token))).dislikedTerms).toEqual([]);
});

test("Alergi baru setelah saran ditawarkan: penerimaan ditolak dan saran tidak berlaku lagi", async () => {
  const a = await actor();
  const r = await J(await run(a.token, "alternatif zeltuk", "zeltuk"));
  const rec = r.recommendations[0];
  const term = rec.candidate.name.split(" ")[1].toLowerCase(); // kata kedua nama, mis. "tempe"
  await call("/api/me/food-preferences", a.token, { kind: "allergy", term });
  const res = await decide(a.token, rec.id, "ACCEPT", rec.version);
  expect(res.status).toBe(409);
  expect((await J(res)).error.code).toBe("RECOMMENDATION_NO_LONGER_ELIGIBLE");
  expect(await prisma.plannedMeal.count({ where: { userId: a.id } })).toBe(0);
  expect((await prisma.recommendation.findUniqueOrThrow({ where: { id: rec.id } })).status).toBe("INVALIDATED");
});

test("Penarikan consent: run menunggu menjadi BLOCKED, saran disembunyikan dan tidak berlaku, keputusan ditolak", async () => {
  const a = await actor();
  const r = await J(await run(a.token, "alternatif zeltuk", "zeltuk"));
  const rec = r.recommendations[0];
  await call("/api/me/consents/withdraw", a.token, { purposes: ["personalized_ai"] });
  const view = await J(await call(`/api/me/agent/runs/${r.id}`, a.token));
  expect(view).toMatchObject({ status: "BLOCKED", safetyDecision: "CONSENT_WITHDRAWN", consentRequired: true, recommendations: [] });
  expect((await decide(a.token, rec.id, "ACCEPT", rec.version)).status).toBe(403);
  expect((await run(a.token, "alternatif zeltuk", "zeltuk")).status).toBe(403);
  expect(await prisma.plannedMeal.count({ where: { userId: a.id } })).toBe(0);
  expect(await prisma.recommendation.count({ where: { userId: a.id, status: "INVALIDATED" } })).toBe(r.recommendations.length);
});

test("Pembatalan, kedaluwarsa, run macet, dan idempotensi pembuatan run", async () => {
  const a = await actor();
  const cancelled = await J(await run(a.token, "alternatif zeltuk", "zeltuk"));
  const c = await J(await call(`/api/me/agent/runs/${cancelled.id}/cancel`, a.token, {}));
  expect(c.status).toBe("CANCELLED");
  expect((await J(await call(`/api/me/agent/runs/${cancelled.id}/cancel`, a.token, {}))).status).toBe("CANCELLED"); // idempoten
  expect((await decide(a.token, cancelled.recommendations[0].id, "ACCEPT", 1)).status).toBe(409);

  const k = key();
  const one = await J(await run(a.token, "alternatif zeltuk", "zeltuk", k));
  const two = await J(await run(a.token, "alternatif zeltuk", "zeltuk", k));
  expect(two.id).toBe(one.id);
  expect(await prisma.agentRun.count({ where: { userId: a.id, idempotencyKey: k } })).toBe(1);
  expect((await run(a.token, "pesan lain", undefined, k)).status).toBe(409);

  await prisma.agentRun.update({ where: { id: one.id }, data: { expiresAt: new Date(Date.now() - 1000) } });
  const expired = await J(await call(`/api/me/agent/runs/${one.id}`, a.token));
  expect(expired.status).toBe("EXPIRED");
  expect(expired.recommendations.every((x: any) => x.status === "EXPIRED")).toBe(true);

  // Proses mati di tengah run: run macet ditandai gagal saat dibaca.
  const stuck = await prisma.agentRun.create({ data: { userId: a.id, status: "RUNNING", intent: "NUTRITION_ALTERNATIVES", inputText: "x", idempotencyKey: key(), expiresAt: new Date(Date.now() + 3_600_000) } });
  await prisma.$executeRawUnsafe(`UPDATE agent_runs SET updated_at = now() - interval '10 minutes' WHERE id = '${stuck.id}'::uuid`);
  expect((await J(await call(`/api/me/agent/runs/${stuck.id}`, a.token))).status).toBe("FAILED");
});

test("Umpan balik konsumsi: hanya untuk saran yang diterima, idempoten, dan tidak membuat catatan makan", async () => {
  const a = await actor();
  const r = await J(await run(a.token, "alternatif zeltuk", "zeltuk"));
  const rec = r.recommendations[0];
  const early = await call(`/api/me/agent/recommendations/${rec.id}/feedback`, a.token, { operationId: crypto.randomUUID(), kind: "CONSUMED" });
  expect(early.status).toBe(409); // belum diterima
  await decide(a.token, rec.id, "ACCEPT", rec.version);
  const meals = await prisma.mealLog.count({ where: { userId: a.id } });
  const op = crypto.randomUUID();
  const fb = await J(await call(`/api/me/agent/recommendations/${rec.id}/feedback`, a.token, { operationId: op, kind: "CONSUMED" }));
  expect(fb.plannedMeal.status).toBe("CONSUMED");
  expect(fb.note).toContain("tidak membuat catatan makan");
  expect((await J(await call(`/api/me/agent/recommendations/${rec.id}/feedback`, a.token, { operationId: op, kind: "CONSUMED" }))).replayed).toBe(true);
  expect((await call(`/api/me/agent/recommendations/${rec.id}/feedback`, a.token, { operationId: crypto.randomUUID(), kind: "NOT_CONSUMED" })).status).toBe(409);
  expect(await prisma.mealLog.count({ where: { userId: a.id } })).toBe(meals);
  expect(await prisma.recommendationFeedback.count({ where: { userId: a.id } })).toBe(1);
});

test("Isolasi akun: akun lain tidak dapat melihat, memutuskan, atau memberi umpan balik pada run/saran milik orang lain", async () => {
  const a = await actor(), b = await actor();
  const r = await J(await run(a.token, "alternatif zeltuk", "zeltuk"));
  const rec = r.recommendations[0];
  expect((await call(`/api/me/agent/runs/${r.id}`, b.token)).status).toBe(404);
  expect((await call(`/api/me/agent/runs/${r.id}/cancel`, b.token, {})).status).toBe(404);
  expect((await decide(b.token, rec.id, "ACCEPT", rec.version)).status).toBe(404);
  expect((await call(`/api/me/agent/recommendations/${rec.id}/feedback`, b.token, { operationId: crypto.randomUUID(), kind: "CONSUMED" })).status).toBe(404);
  expect((await J(await call("/api/me/planned-meals", b.token))).items).toEqual([]);
  // Kunci idempotensi sama pada akun lain adalah run terpisah.
  const k = key();
  const ra = await J(await run(a.token, "alternatif zeltuk", "zeltuk", k)), rb = await J(await run(b.token, "alternatif zeltuk", "zeltuk", k));
  expect(ra.id).not.toBe(rb.id);
  // Saran A tidak berubah.
  expect((await prisma.recommendation.findUniqueOrThrow({ where: { id: rec.id } })).status).toBe("OFFERED");
});

test("Alat: tidak terdaftar, maksud tidak diizinkan, argumen tidak valid, dan anggaran dibatasi; userId tidak datang dari argumen", async () => {
  const a = await actor(), b = await actor();
  const mk = (over: Partial<ToolContext> = {}) => prisma.agentRun.create({ data: { userId: a.id, status: "RUNNING", intent: "NUTRITION_ALTERNATIVES", inputText: "x", idempotencyKey: key(), expiresAt: new Date(Date.now() + 3_600_000) } }).then((r): ToolContext => ({ userId: a.id, runId: r.id, intent: "NUTRITION_ALTERNATIVES", maxCalls: 8, callsUsed: 0, ...over }));
  const code = async (p: Promise<unknown>) => { try { await p; return "OK"; } catch (e) { return e instanceof ToolError ? e.code : "OTHER"; } };

  expect(await code(executeTool(await mk(), "run_sql", { q: "select 1" }))).toBe("UNKNOWN_TOOL");
  expect(await code(executeTool(await mk({ intent: "OTHER" }), "get_food_preferences", {}))).toBe("INTENT_NOT_ALLOWED");
  expect(await code(executeTool(await mk(), "search_food_reference", { query: "a" }))).toBe("INVALID_ARGUMENTS");
  expect(await code(executeTool(await mk(), "search_food_reference", { query: "zeltuk", userId: b.id }))).toBe("INVALID_ARGUMENTS"); // argumen asing ditolak (strict)
  expect(await code(executeTool(await mk({ callsUsed: 8 }), "get_food_preferences", {}))).toBe("BUDGET_EXCEEDED");

  // Alat memakai userId dari konteks run: preferensi akun B tidak bocor ke run milik A.
  await prisma.foodPreference.create({ data: { userId: b.id, kind: "allergy", term: "udang", label: "Udang", severity: "strict" } });
  const prefs = await executeTool<any[]>(await mk(), "get_food_preferences", {});
  expect(prefs).toEqual([]);
  // Penolakan juga tercatat.
  expect(await prisma.agentToolCall.count({ where: { status: "DENIED", errorCode: "UNKNOWN_TOOL" } })).toBeGreaterThanOrEqual(1);
});

test("Pesan tak didukung dan butuh klarifikasi tidak memanggil alat dan tidak membuat saran", async () => {
  const a = await actor();
  const off = await J(await run(a.token, "ceritakan lelucon tentang kucing"));
  expect(off).toMatchObject({ status: "COMPLETED", intent: "UNSUPPORTED", recommendations: [] });
  const clarify = await J(await run(a.token, "makan apa yang bisa"));
  expect(clarify.status).toBe("COMPLETED");
  expect(clarify.message).toContain("Makanan apa");
  expect(await prisma.agentToolCall.count({ where: { run: { userId: a.id } } })).toBe(0);
});

test("Tidak ada kandidat bersumber → INSUFFICIENT_DATA tanpa angka karangan", async () => {
  const a = await actor();
  const r = await J(await run(a.token, "alternatif qqxxzzvv", "qqxxzzvv"));
  expect(r.status).toBe("COMPLETED");
  expect(r.recommendations).toEqual([]);
  expect(r.message).toContain("Tidak ada kandidat");
});
