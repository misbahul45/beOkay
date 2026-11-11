import { afterAll, beforeAll, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { ToolError, executeTool } from "../../src/features/agent/agent.tools.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
const J = async (r: Response) => (await r.json()) as any;
const ALL = ["health_data_processing", "descriptive_summaries", "personalized_ai"];
async function actor(purposes: string[] = ALL) {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "Fixture", email: `cv-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  const policy = await J(await call("/api/consent-policies/current", token));
  await call("/api/me/consents", token, { policyVersion: policy.version, purposes });
  await call("/api/me/preferences", token, { timezone: "Asia/Jakarta" }, "PATCH");
  return { id, token };
}
const say = (token: string, thread: string, text: string, clientMessageId: string = crypto.randomUUID()) => call(`/api/me/conversations/${thread}/messages`, token, { clientMessageId, text });
const partsOf = (r: any) => r.assistantMessage.parts as any[];
const part = (r: any, type: string) => partsOf(r).find((p) => p.type === type);

const food = [
  ["ZZCV01", "Zelvor goreng", 300, 30, 8, 15],
  ["ZZCV02", "Zelvor kukus", 120, 20, 6, 2],
  ["ZZCV03", "Ayam zelpak goreng", 260, 2, 20, 18],
] as const;
beforeAll(async () => {
  for (const [code, name, cal, carb, protein, fat] of food)
    await prisma.$executeRawUnsafe(`INSERT INTO food_reference (code,name,name_normalized,source,source_version,source_ref,page,chapter,status,calories,carbohydrates,protein,fat,updated_at) VALUES ('${code}','${name}','${name.toLowerCase()}','Tabel Komposisi Pangan Indonesia','TKPI 2017','KZGMI-2001',30,'4.1. UJI','verified_auto',${cal},${carb},${protein},${fat},now())`);
});
afterAll(async () => {
  await prisma.$executeRawUnsafe(`DELETE FROM food_reference WHERE code LIKE 'ZZCV%'`);
  await prisma.users.deleteMany({ where: { id: { in: users } } });
});

test("Akses: butuh login dan consent kesehatan; thread milik orang lain tidak terlihat", async () => {
  const a = await actor(), b = await actor(), none = await actor([]);
  const t = crypto.randomUUID();
  expect((await say("", t, "halo")).status).toBe(401);
  expect((await say(none.token, t, "halo")).status).toBe(403);
  expect((await say(a.token, t, "halo")).status).toBe(201);
  expect((await call(`/api/me/conversations/${t}`, b.token)).status).toBe(404);
  expect((await say(b.token, t, "halo")).status).toBe(404);
  expect((await call(`/api/me/conversations/${t}`, b.token, undefined, "DELETE")).status).toBe(404);
  expect((await J(await call("/api/me/conversations", b.token))).items).toEqual([]);
});

test("Sapaan membuat thread; pesan idempoten lewat clientMessageId", async () => {
  const a = await actor();
  const t = crypto.randomUUID(), m = crypto.randomUUID();
  const first = await J(await say(a.token, t, "Halo!", m));
  expect(first).toMatchObject({ replayed: false, thread: { id: t, title: "Halo!", messageCount: 2 }, userMessage: { seq: 1, role: "USER" }, assistantMessage: { seq: 2, role: "ASSISTANT", route: "GREETING" } });
  expect(part(first, "suggestions").items.length).toBe(4);
  const again = await say(a.token, t, "Halo!", m);
  expect(again.status).toBe(200);
  expect(await J(again)).toMatchObject({ replayed: true, assistantMessage: { id: first.assistantMessage.id } });
  expect((await say(a.token, t, "Hai lagi", m)).status).toBe(409);
  expect(await prisma.conversationMessage.count({ where: { threadId: t } })).toBe(2);
  const list = await J(await call("/api/me/conversations", a.token));
  expect(list.items[0]).toMatchObject({ id: t, messageCount: 2 });
});

test("Ringkasan aktivitas memakai mesin statistik; tanpa consent ringkasan minta persetujuan", async () => {
  const a = await actor();
  const hash = () => createHash("sha256").update(crypto.randomUUID()).digest("hex");
  const at = new Date(Date.now() - 3 * 3_600_000);
  await prisma.activitySession.create({ data: { userId: a.id, activityType: "walking", startedAt: at, endedAt: new Date(at.getTime() + 30 * 60_000), durationMinutes: 30, createHash: hash() } });
  const r = await J(await say(a.token, crypto.randomUUID(), "aktivitasku minggu ini gimana?"));
  expect(r.assistantMessage.route).toBe("STATS");
  expect(part(r, "statistic")).toMatchObject({ statisticId: "activity.total_minutes", value: 30, unit: "menit", days: 7 });
  expect(partsOf(r)[0].text).toContain("30 menit aktivitas di 1 hari");
  expect(JSON.stringify(partsOf(r))).not.toContain("stats-v1");

  const b = await actor(["health_data_processing", "personalized_ai"]);
  const blocked = await J(await say(b.token, crypto.randomUUID(), "aktivitasku minggu ini gimana?"));
  expect(part(blocked, "consent_required")).toMatchObject({ purpose: "descriptive_summaries" });
});

test("Makanan: hanya kecocokan identitas yang ditawarkan, setujui dari percakapan, lanjutan, dan tidak ketemu", async () => {
  const a = await actor();
  const t = crypto.randomUUID();
  const r = await J(await say(a.token, t, "cari info zelvor goreng"));
  expect(r.assistantMessage.route).toBe("FOOD");
  const recs = part(r, "recommendations");
  expect(recs.items[0]).toMatchObject({ name: "Zelvor goreng", match: "EXACT", status: "OFFERED", type: "NUTRITION" });
  expect(recs.items.map((x: any) => x.name)).not.toContain("Ayam zelpak goreng");
  expect(await prisma.plannedMeal.count({ where: { userId: a.id } })).toBe(0);

  const top = recs.items[0];
  expect((await call(`/api/me/agent/recommendations/${top.id}/decision`, a.token, { operationId: crypto.randomUUID(), decision: "ACCEPT", expectedVersion: top.version })).status).toBe(200);
  const view = await J(await call(`/api/me/conversations/${t}`, a.token));
  const hydrated = view.messages.at(-1).parts.find((p: any) => p.type === "recommendations");
  expect(hydrated.items[0]).toMatchObject({ id: top.id, status: "ACCEPTED" });

  const why = await J(await say(a.token, t, "Kenapa ini disarankan?"));
  expect(why.assistantMessage.route).toBe("FOLLOW_UP");
  expect(partsOf(why)[0].text).toContain("Zelvor goreng");

  const probe = await J(await say(a.token, crypto.randomUUID(), "zelvor kukus"));
  expect(part(probe, "recommendations").items[0]).toMatchObject({ name: "Zelvor kukus", match: "EXACT" });

  const miss = await J(await say(a.token, crypto.randomUUID(), "cari info zelmon goreng"));
  expect(part(miss, "no_match")).toMatchObject({ query: "zelmon goreng" });
  expect(part(miss, "recommendations")).toBeUndefined();

  const unknown = await J(await say(a.token, crypto.randomUUID(), "zelmon goreng"));
  expect(unknown.assistantMessage.route).toBe("UNKNOWN");
});

test("Keselamatan dan consent asisten: tidak ada run atau saran yang dibuat", async () => {
  const a = await actor();
  const runsBefore = await prisma.agentRun.count({ where: { userId: a.id } });
  const s = await J(await say(a.token, crypto.randomUUID(), "boleh naikkan dosis metformin?"));
  expect(part(s, "safety")).toMatchObject({ code: "MEDICATION_ADVICE", title: "Perlu tenaga kesehatan" });
  expect(await prisma.agentRun.count({ where: { userId: a.id } })).toBe(runsBefore);

  const b = await actor(["health_data_processing", "descriptive_summaries"]);
  const c = await J(await say(b.token, crypto.randomUUID(), "cari info zelvor goreng"));
  expect(part(c, "consent_required")).toMatchObject({ purpose: "personalized_ai" });
  expect(await prisma.recommendation.count({ where: { userId: b.id } })).toBe(0);
});

test("Hapus percakapan: pesan hilang, saran terbuka tidak berlaku, teks run disamarkan; ekspor memuat percakapan", async () => {
  const a = await actor();
  const keep = crypto.randomUUID(), gone = crypto.randomUUID();
  await say(a.token, keep, "halo");
  const r = await J(await say(a.token, gone, "cari info zelvor kukus"));
  const runId = part(r, "recommendations").runId;
  const exp = await J(await call("/api/me/export", a.token));
  expect(exp.data.conversations.map((c: any) => c.id).sort()).toEqual([keep, gone].sort());
  expect(exp.counts.conversations).toBe(2);

  const del = await J(await call(`/api/me/conversations/${gone}`, a.token, undefined, "DELETE"));
  expect(del).toMatchObject({ deleted: true, id: gone, messages: 2 });
  expect(await prisma.conversationMessage.count({ where: { threadId: gone } })).toBe(0);
  expect(await prisma.recommendation.count({ where: { runId, status: "OFFERED" } })).toBe(0);
  expect((await prisma.agentRun.findUniqueOrThrow({ where: { id: runId } })).inputText).toBe("(percakapan dihapus)");
  expect(await prisma.auditEvent.count({ where: { userId: a.id, eventType: "conversation_deleted" } })).toBe(1);
  expect((await call(`/api/me/conversations/${gone}`, a.token)).status).toBe(404);
  expect((await J(await call("/api/me/conversations", a.token))).items.map((x: any) => x.id)).toEqual([keep]);
});

test("Alat menolak pemanggilan tanpa persetujuan yang disyaratkan", async () => {
  const a = await actor(["health_data_processing"]);
  const run = await prisma.agentRun.create({ data: { userId: a.id, status: "RUNNING", intent: "NUTRITION_ALTERNATIVES", inputText: "x", idempotencyKey: `k-${crypto.randomUUID()}`, expiresAt: new Date(Date.now() + 3_600_000) } });
  let code = "OK";
  try {
    await executeTool({ userId: a.id, runId: run.id, intent: "NUTRITION_ALTERNATIVES", maxCalls: 8, callsUsed: 0 }, "get_personalization", {});
  } catch (e) {
    code = e instanceof ToolError ? e.code : "OTHER";
  }
  expect(code).toBe("PERMISSION_DENIED");
  expect(await prisma.agentToolCall.count({ where: { runId: run.id, status: "DENIED", errorCode: "PERMISSION_DENIED" } })).toBe(1);
});
