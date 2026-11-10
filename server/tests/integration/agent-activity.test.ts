import { afterAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { ToolError, executeTool } from "../../src/features/agent/agent.tools.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
const J = async (r: Response) => (await r.json()) as any;
async function actor() {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "Fixture", email: `aa-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  const policy = (await (await call("/api/consent-policies/current", token)).json()) as any;
  await call("/api/me/consents", token, { policyVersion: policy.version, purposes: ["health_data_processing", "personalized_ai"] });
  await call("/api/me/preferences", token, { timezone: "Asia/Jakarta" }, "PATCH");
  return { id, token };
}
afterAll(async () => { await prisma.users.deleteMany({ where: { id: { in: users } } }); });
const run = (token: string, message: string) => call("/api/me/agent/runs", token, { idempotencyKey: `k-${crypto.randomUUID()}`, message });
const decide = (token: string, id: string, decision: "ACCEPT" | "REJECT", v = 1, op: string = crypto.randomUUID()) => call(`/api/me/agent/recommendations/${id}/decision`, token, { operationId: op, decision, expectedVersion: v });
async function log(token: string, type: string, minutes: number, daysAgo: number) {
  const res = await call("/api/me/activities", token, { id: crypto.randomUUID(), activityType: type, startedAt: new Date(Date.now() - daysAgo * 86_400_000 - (minutes + 2) * 60_000).toISOString(), durationMinutes: minutes });
  expect(res.status).toBe(201);
  return (await J(res)).id as string;
}

test("Tanpa riwayat dan tanpa jam tangan: satu contoh awal, ditandai kurang data, tidak ada nilai karangan", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor();
  const r = await J(await run(a.token, "rekomendasi olahraga ringan untuk besok"));
  expect(r).toMatchObject({ status: "WAITING_FOR_USER", intent: "ACTIVITY_PLAN" });
  expect(r.recommendations).toHaveLength(1);
  const rec = r.recommendations[0];
  expect(rec).toMatchObject({ type: "ACTIVITY", activity: { type: "walking", durationMinutes: 10 }, dataCoverage: "PARTIAL" });
  expect(rec.candidate.provenance).toContain("belum ada riwayat");
  expect(rec.limitations.join(" ")).toContain("bukan resep olahraga");
  expect(JSON.stringify(rec)).not.toMatch(/kalori|kkal|denyut|menurunkan gula|menyembuhkan/i);
  expect(r.events.map((e: any) => e.type)).toEqual(expect.arrayContaining(["CONTEXT_READY", "CANDIDATES_BUILT", "RECOMMENDATIONS_OFFERED"]));
  expect(await prisma.agentToolCall.count({ where: { runId: r.id, status: "OK" } })).toBe(3);
});

test("Dengan riwayat manual: kandidat tidak melebihi sesi terpanjang dan teks menyatakan jam tangan tidak diperlukan", async () => {
  const a = await actor();
  for (const [t, m, d] of [["walking", 20, 1], ["walking", 30, 2], ["walking", 40, 3], ["walking", 25, 4], ["cycling", 30, 5]] as const) await log(a.token, t, m, d);
  const r = await J(await run(a.token, "olahraga apa yang bisa saya lakukan minggu ini"));
  expect(r.recommendations.length).toBeGreaterThanOrEqual(2);
  expect(r.recommendations.length).toBeLessThanOrEqual(3);
  for (const rec of r.recommendations) {
    const cap = rec.activity.type === "walking" ? 40 : 30;
    expect(rec.activity.durationMinutes).toBeLessThanOrEqual(cap); // tidak ada eskalasi
    expect(rec.limitations.join(" ")).toContain("jam tangan tidak diperlukan");
    expect(rec.dataCoverage).toBe("COMPLETE");
  }
  expect(r.recommendations[0].activity.type).toBe("walking");
});

test("Persetujuan: membuat rencana aktivitas (bukan sesi), idempoten, versi dijaga; menolak tidak menulis apa pun", async () => {
  const a = await actor();
  await log(a.token, "walking", 30, 1);
  await log(a.token, "walking", 30, 2);
  const r = await J(await run(a.token, "rekomendasi olahraga"));
  const rec = r.recommendations[0];
  const sessionsBefore = await prisma.activitySession.count({ where: { userId: a.id } });
  const op = crypto.randomUUID();
  const ok = await J(await decide(a.token, rec.id, "ACCEPT", rec.version, op));
  expect(ok).toMatchObject({ replayed: false, recommendation: { status: "ACCEPTED" } });
  expect(ok.activityPlanId).toBeTruthy();
  expect((await J(await decide(a.token, rec.id, "ACCEPT", rec.version, op))).replayed).toBe(true);
  expect(await prisma.activityPlan.count({ where: { userId: a.id } })).toBe(1);
  expect(await prisma.activitySession.count({ where: { userId: a.id } })).toBe(sessionsBefore); // rencana ≠ sesi
  const plans = await J(await call("/api/me/activity-plans", a.token));
  expect(plans.items[0]).toMatchObject({ status: "CONFIRMED", activityType: "walking" });
  // Menolak saran lain pada run yang sama: tidak ada rencana baru dan tidak ada personalisasi makanan.
  const other = r.recommendations[1];
  if (other) {
    const rej = await J(await decide(a.token, other.id, "REJECT", other.version));
    expect(rej.personalizationVersion).toBeNull();
    expect(await prisma.activityPlan.count({ where: { userId: a.id } })).toBe(1);
  }
});

test("Umpan balik: selesai (dengan sesi milik sendiri) atau dilewati; jenis salah, sesi orang lain, dan pengulangan ditangani", async () => {
  const a = await actor(), b = await actor();
  await log(a.token, "walking", 30, 1);
  const mine = await log(a.token, "walking", 30, 0);
  const foreign = await log(b.token, "walking", 30, 0);
  const r = await J(await run(a.token, "olahraga"));
  const rec = r.recommendations[0];
  const fb = (body: object, token = a.token) => call(`/api/me/agent/recommendations/${rec.id}/feedback`, token, body);
  expect((await fb({ operationId: crypto.randomUUID(), kind: "COMPLETED" })).status).toBe(409); // belum diterima
  await decide(a.token, rec.id, "ACCEPT", rec.version);
  expect((await fb({ operationId: crypto.randomUUID(), kind: "CONSUMED" })).status).toBe(422); // jenis tidak cocok
  expect((await fb({ operationId: crypto.randomUUID(), kind: "COMPLETED", activitySessionId: foreign })).status).toBe(422); // sesi orang lain
  const op = crypto.randomUUID();
  const done = await J(await fb({ operationId: op, kind: "COMPLETED", activitySessionId: mine }));
  expect(done.activityPlan).toMatchObject({ status: "COMPLETED", linkedSessionId: mine });
  expect(done.note).toContain("tidak membuat sesi aktivitas");
  expect((await J(await fb({ operationId: op, kind: "COMPLETED", activitySessionId: mine }))).replayed).toBe(true);
  expect((await fb({ operationId: crypto.randomUUID(), kind: "SKIPPED" })).status).toBe(409); // sudah tercatat
  expect((await fb({ operationId: crypto.randomUUID(), kind: "SKIPPED" }, b.token)).status).toBe(404); // akun lain
});

test("Keselamatan: eskalasi dan cedera dihentikan sebelum alat berjalan", async () => {
  const a = await actor();
  for (const [msg, code] of [["tolong tambah intensitas olahraga saya", "INTENSITY_ESCALATION"], ["lutut saya cedera, olahraga apa?", "INJURY_OR_PAIN"]] as const) {
    const r = await J(await run(a.token, msg));
    expect(r).toMatchObject({ status: "BLOCKED", safetyDecision: code, recommendations: [] });
    expect(await prisma.agentToolCall.count({ where: { runId: r.id } })).toBe(0);
  }
  expect(await prisma.activityPlan.count({ where: { userId: a.id } })).toBe(0);
});

test("Alat konteks aktivitas hanya untuk maksud aktivitas dan hanya membaca data milik run; sesi yang diarsipkan tidak dihitung", async () => {
  const a = await actor(), b = await actor();
  await log(b.token, "running", 60, 1); // data akun lain
  const sid = await log(a.token, "walking", 30, 1);
  await call(`/api/me/activities/${sid}`, a.token, { expectedVersion: 1, reason: "Salah", archived: true }, "PATCH");
  const mk = (intent: string) => prisma.agentRun.create({ data: { userId: a.id, status: "RUNNING", intent, inputText: "x", idempotencyKey: `k-${crypto.randomUUID()}`, expiresAt: new Date(Date.now() + 3_600_000) } }).then((r) => ({ userId: a.id, runId: r.id, intent, maxCalls: 8, callsUsed: 0 }));
  const ctx = await mk("ACTIVITY_PLAN");
  const h = await executeTool<{ sessions: unknown[] }>(ctx, "get_activity_context", {});
  expect(h.sessions).toEqual([]); // arsip dan akun lain tidak ikut
  let code = "OK";
  try { await executeTool(await mk("NUTRITION_ALTERNATIVES"), "get_activity_context", {}); } catch (e) { code = e instanceof ToolError ? e.code : "OTHER"; }
  expect(code).toBe("INTENT_NOT_ALLOWED");
  let code2 = "OK";
  try { await executeTool(await mk("ACTIVITY_PLAN"), "search_food_reference", { query: "tempe" }); } catch (e) { code2 = e instanceof ToolError ? e.code : "OTHER"; }
  expect(code2).toBe("INTENT_NOT_ALLOWED");
});
