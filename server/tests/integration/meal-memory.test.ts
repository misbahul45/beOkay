import { afterAll, beforeAll, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { prisma } from "../../src/infrastructure/database/prisma.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
const J = async (r: Response) => (await r.json()) as any;
const ALL = ["health_data_processing", "descriptive_summaries", "personalized_ai"];
async function actor(purposes: string[] = ALL) {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "Fixture", email: `mm-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  const policy = await J(await call("/api/consent-policies/current", token));
  await call("/api/me/consents", token, { policyVersion: policy.version, purposes });
  await call("/api/me/preferences", token, { timezone: "Asia/Jakarta" }, "PATCH");
  return { id, token };
}
const say = (token: string, thread: string, text: string, extra: object = {}, clientMessageId: string = crypto.randomUUID()) =>
  call(`/api/me/conversations/${thread}/messages`, token, { clientMessageId, text, ...extra });
const part = (r: any, type: string) => (r.assistantMessage.parts as any[]).find((p) => p.type === type);
const parts = (r: any, type: string) => (r.assistantMessage.parts as any[]).filter((p) => p.type === type);
const hash = () => createHash("sha256").update(crypto.randomUUID()).digest("hex");

const food = [
  ["ZZMD01", "Zelnasi putih", 180, 39.8, 3, 0.3],
  ["ZZMD02", "Zelayam bakar", 249, 0, 26, 15],
] as const;
beforeAll(async () => {
  for (const [code, name, cal, carb, protein, fat] of food)
    await prisma.$executeRawUnsafe(`INSERT INTO food_reference (code,name,name_normalized,source,source_version,source_ref,page,chapter,status,calories,carbohydrates,protein,fat,updated_at) VALUES ('${code}','${name}','${name.toLowerCase()}','Tabel Komposisi Pangan Indonesia','TKPI 2017','KZGMI-2001',30,'4.1. UJI','verified_auto',${cal},${carb},${protein},${fat},now())`);
});
afterAll(async () => {
  await prisma.$executeRawUnsafe(`DELETE FROM food_reference WHERE code LIKE 'ZZMD%'`);
  await prisma.users.deleteMany({ where: { id: { in: users } } });
});

test("Catat makan dari kalimat: draf dulu, simpan hanya setelah konfirmasi, tepat sekali", async () => {
  const a = await actor(), b = await actor();
  const t = crypto.randomUUID();
  const mealsBefore = await prisma.mealLog.count({ where: { userId: a.id } });
  const r = await J(await say(a.token, t, "tadi siang makan zelnasi putih satu piring, zelayam bakar, dan zelkoi"));
  expect(r.assistantMessage.route).toBe("MEAL_LOG");
  const d = part(r, "meal_draft").draft;
  expect(d).toMatchObject({ status: "PROPOSED", source: "TEXT", category: "lunch", version: 1 });
  expect(d.items.map((i: any) => i.name)).toEqual(["zelnasi putih", "zelayam bakar", "zelkoi"]);
  expect(d.items[0]).toMatchObject({ unitLabel: "piring", grams: null, selected: "tkpi:ZZMD01" });
  expect(d.items[0].candidates[0]).toMatchObject({ kind: "TKPI", name: "Zelnasi putih", match: "EXACT" });
  expect(d.items[2].candidates).toEqual([]);
  expect(r.assistantMessage.basis.sources.map((s: any) => s.kind)).toEqual(["MESSAGE", "FOOD_REFERENCE"]);
  expect(await prisma.mealLog.count({ where: { userId: a.id } })).toBe(mealsBefore);

  expect((await call(`/api/me/meal-drafts/${d.id}`, b.token)).status).toBe(404);
  const items = [
    { index: 0, candidateKey: "tkpi:ZZMD01", name: "zelnasi putih", quantity: 1, unit: "portion", grams: 150 },
    { index: 1, candidateKey: "tkpi:ZZMD02", name: "zelayam bakar", quantity: 1, unit: "portion", grams: null },
    { index: 2, candidateKey: null, name: "zelkoi", quantity: 1, unit: "portion", grams: null },
  ];
  const body = { expectedVersion: 1, category: "lunch", consumedAt: d.consumedAt, items };
  expect((await call(`/api/me/meal-drafts/${d.id}/confirm`, a.token, { ...body, items: [{ ...items[0], candidateKey: `food:${crypto.randomUUID()}` }] })).status).toBe(422);
  expect((await call(`/api/me/meal-drafts/${d.id}/confirm`, a.token, { ...body, expectedVersion: 2 })).status).toBe(409);
  expect((await call(`/api/me/meal-drafts/${d.id}/confirm`, b.token, body)).status).toBe(404);
  const saved = await call(`/api/me/meal-drafts/${d.id}/confirm`, a.token, body);
  expect(saved.status).toBe(201);
  const s = await J(saved);
  expect(s).toMatchObject({ replayed: false, mealId: d.id, draft: { status: "SAVED", mealId: d.id } });
  const replay = await call(`/api/me/meal-drafts/${d.id}/confirm`, a.token, body);
  expect(replay.status).toBe(200);
  expect(await prisma.mealLog.count({ where: { userId: a.id } })).toBe(mealsBefore + 1);
  const meal = await J(await call(`/api/me/meals/${d.id}`, a.token));
  expect(meal.items).toHaveLength(3);
  const byName = (n: string) => meal.items.find((i: any) => i.name === n);
  expect(byName("Zelnasi putih").nutrition.calories).toBe(270);
  expect(byName("Zelayam bakar").nutrition.calories).toBeNull();
  expect(byName("zelkoi").foodId).toBeNull();
  expect(await prisma.foodCatalog.count({ where: { userId: a.id, sourceVersion: "ZZMD01" } })).toBe(1);
  expect((await call(`/api/me/meal-drafts/${d.id}/discard`, a.token, {})).status).toBe(409);

  const view = await J(await call(`/api/me/conversations/${t}`, a.token));
  expect(view.messages.at(-1).parts.find((p: any) => p.type === "meal_draft").draft.status).toBe("SAVED");
});

test("Takaran porsi milik pengguna dipakai sebagai perkiraan; tanpa takaran berat tetap kosong", async () => {
  const a = await actor();
  const t = crypto.randomUUID();
  const first = await J(await say(a.token, t, "aku makan zelnasi putih 2 piring"));
  const d1 = part(first, "meal_draft").draft;
  expect(d1.items[0]).toMatchObject({ quantity: 2, unitLabel: "piring", grams: null });
  await J(await call(`/api/me/meal-drafts/${d1.id}/confirm`, a.token, { expectedVersion: 1, category: d1.category, consumedAt: d1.consumedAt, items: [{ index: 0, candidateKey: "tkpi:ZZMD01", name: "zelnasi putih", quantity: 2, unit: "portion", grams: null }] }));
  const foodRow = await prisma.foodCatalog.findFirstOrThrow({ where: { userId: a.id, sourceVersion: "ZZMD01" } });
  await prisma.foodPortionMeasure.create({ data: { userId: a.id, foodId: foodRow.id, label: "piring", grams: 200, basis: "user_estimate" } });
  const second = await J(await say(a.token, t, "barusan makan zelnasi putih 2 piring"));
  const d2 = part(second, "meal_draft").draft;
  expect(d2.items[0]).toMatchObject({ selected: `food:${foodRow.id}`, grams: 400, gramsBasis: "user_estimate" });
  expect(second.assistantMessage.basis.sources.map((s: any) => s.kind)).toContain("PORTION_MEASURES");
});

test("Foto di percakapan: nama dari model diperlakukan sebagai dugaan, porsi wajib dikonfirmasi", async () => {
  const a = await actor();
  const t = crypto.randomUUID();
  const m = crypto.randomUUID();
  const photo = { items: [{ name: "Zelayam bakar", confidence: "medium" }, { name: "x", confidence: "low" }] };
  expect((await say(a.token, t, "Foto makanan", { photo: { items: [{ name: "ab", confidence: "maybe" }] } })).status).toBe(400);
  const r = await J(await say(a.token, t, "Foto makanan", { photo: { items: [photo.items[0]] } }, m));
  expect(r.assistantMessage.route).toBe("PHOTO_MEAL");
  expect(r.userMessage.parts[0]).toEqual({ type: "photo", items: [{ name: "Zelayam bakar", confidence: "medium" }] });
  const d = part(r, "meal_draft").draft;
  expect(d).toMatchObject({ source: "PHOTO", status: "PROPOSED" });
  expect(d.items[0]).toMatchObject({ name: "zelayam bakar", photoConfidence: "medium", quantityStated: false, grams: null, selected: "tkpi:ZZMD02" });
  expect(r.assistantMessage.basis.sources[0]).toEqual({ kind: "PHOTO", label: "Nama makanan dari foto (perkiraan model)" });
  expect((await say(a.token, t, "Foto makanan", { photo: { items: [{ name: "Zelnasi putih", confidence: "high" }] } }, m)).status).toBe(409);
  expect(await prisma.mealLog.count({ where: { userId: a.id } })).toBe(0);
});

test("Memori: diusulkan dari pernyataan, aktif hanya setelah dikonfirmasi, dipakai untuk saran aktivitas, bisa diubah dan dihapus", async () => {
  const a = await actor(), b = await actor();
  const at = new Date(Date.now() - 2 * 86_400_000);
  for (let i = 0; i < 4; i++) {
    const s = new Date(at.getTime() - i * 86_400_000);
    await prisma.activitySession.create({ data: { userId: a.id, activityType: "walking", startedAt: s, endedAt: new Date(s.getTime() + 30 * 60_000), durationMinutes: 30, createHash: hash() } });
  }
  const t = crypto.randomUUID();
  const r = await J(await say(a.token, t, "aku lebih suka olahraga pagi dan cuma bisa 15 menit"));
  const proposals = parts(r, "memory_proposal");
  expect(proposals.map((p: any) => p.memory.content).sort()).toEqual(["Lebih suka beraktivitas pagi hari", "Punya waktu sekitar 15 menit untuk aktivitas"]);
  expect(proposals.every((p: any) => p.memory.status === "PROPOSED")).toBe(true);
  expect((await J(await call("/api/me/memories", a.token))).items).toEqual([]);

  const minutes = proposals.find((p: any) => p.memory.kind === "AVAILABLE_MINUTES").memoryId;
  const time = proposals.find((p: any) => p.memory.kind === "ACTIVITY_TIME").memoryId;
  expect((await call(`/api/me/memories/${minutes}/confirm`, b.token, {})).status).toBe(404);
  expect((await J(await call(`/api/me/memories/${minutes}/confirm`, a.token, {}))).status).toBe("ACTIVE");
  expect((await J(await call(`/api/me/memories/${time}/dismiss`, a.token, {}))).status).toBe("DISMISSED");
  const again = await J(await say(a.token, crypto.randomUUID(), "aku lebih suka olahraga pagi dan cuma bisa 15 menit"));
  expect(parts(again, "memory_proposal")).toEqual([]);

  const plan = await J(await say(a.token, crypto.randomUUID(), "ide olahraga ringan"));
  const recs = part(plan, "recommendations").items;
  expect(recs.length).toBeGreaterThan(0);
  expect(recs.every((x: any) => x.activity.durationMinutes <= 15)).toBe(true);
  expect(plan.assistantMessage.basis.memories.map((m: any) => m.content)).toEqual(["Punya waktu sekitar 15 menit untuk aktivitas"]);
  expect(plan.assistantMessage.basis.sources.map((s: any) => s.kind)).toContain("ACTIVITY_HISTORY");

  const list = await J(await call("/api/me/memories", a.token));
  expect(list).toMatchObject({ enabled: true, consentGiven: true, active: true });
  const item = list.items[0];
  expect((await call(`/api/me/memories/${item.id}`, a.token, { content: "Punya waktu sekitar 20 menit untuk aktivitas", expectedVersion: 9 }, "PATCH")).status).toBe(409);
  const edited = await J(await call(`/api/me/memories/${item.id}`, a.token, { content: "Punya waktu sekitar 20 menit untuk aktivitas", expectedVersion: 1 }, "PATCH"));
  expect(edited).toMatchObject({ version: 2, sourceType: "USER" });
  expect((await call(`/api/me/memories/${item.id}`, b.token, undefined, "DELETE")).status).toBe(404);

  await call("/api/me/memory-preferences", a.token, { enabled: false }, "PATCH");
  const off = await J(await say(a.token, crypto.randomUUID(), "aku sibuk tiap sore"));
  expect(parts(off, "memory_proposal")).toEqual([]);
  const plan2 = await J(await say(a.token, crypto.randomUUID(), "ide olahraga ringan"));
  expect(plan2.assistantMessage.basis.memories).toEqual([]);
  expect(part(plan2, "recommendations").items.some((x: any) => x.activity.durationMinutes > 15)).toBe(true);
  expect((await call(`/api/me/memories/${item.id}/confirm`, a.token, {})).status).toBe(403);

  expect((await J(await call(`/api/me/memories/${item.id}`, a.token, undefined, "DELETE"))).deleted).toBe(true);
  expect((await J(await call("/api/me/memories", a.token, undefined, "DELETE"))).deleted).toBeGreaterThanOrEqual(1);
  expect(await prisma.memoryItem.count({ where: { userId: a.id } })).toBe(0);
  expect(await prisma.auditEvent.count({ where: { userId: a.id, eventType: { startsWith: "memory_" } } })).toBeGreaterThanOrEqual(4);
});

test("Memori tanpa persetujuan saran personal: tidak ada usulan, tetap bisa dilihat dan dihapus; topik sensitif tidak diusulkan", async () => {
  const noAi = await actor(["health_data_processing", "descriptive_summaries"]);
  const r = await J(await say(noAi.token, crypto.randomUUID(), "aku lebih suka olahraga pagi"));
  expect(parts(r, "memory_proposal")).toEqual([]);
  expect(await J(await call("/api/me/memories", noAi.token))).toMatchObject({ consentGiven: false, active: false, items: [] });
  const a = await actor();
  const s = await J(await say(a.token, crypto.randomUUID(), "aku lebih suka minum obat pagi"));
  expect(parts(s, "memory_proposal")).toEqual([]);
  expect(await prisma.memoryItem.count({ where: { userId: a.id } })).toBe(0);
});

test("Ekspor memuat draf makan dan memori; hapus percakapan membuang draf yang masih terbuka", async () => {
  const a = await actor();
  const t = crypto.randomUUID();
  const r = await J(await say(a.token, t, "barusan makan zelayam bakar"));
  const d = part(r, "meal_draft").draft;
  await J(await say(a.token, crypto.randomUUID(), "aku sibuk tiap sore"));
  const exp = await J(await call("/api/me/export", a.token));
  expect(exp.data.mealDrafts.map((x: any) => x.id)).toContain(d.id);
  expect(exp.data.memories.map((x: any) => x.content)).toContain("Sering sibuk di sore hari");
  await call(`/api/me/conversations/${t}`, a.token, undefined, "DELETE");
  const row = await prisma.mealDraft.findUniqueOrThrow({ where: { id: d.id } });
  expect(row).toMatchObject({ status: "DISCARDED", threadId: null });
});

test("Cari di web (Firecrawl) lewat alat terdaftar: hanya atas permintaan, angka per 100 g yang lolos parser, ditandai web, tercatat sebagai run alat", async () => {
  const { mealDraftService } = await import("../../src/features/meal-drafts/meal-draft.service.ts");
  const { webSearchRef } = await import("../../src/features/agent/agent.tools.ts");
  const a = await actor();
  const r = await J(await say(a.token, crypto.randomUUID(), "barusan makan zelvoli bakar"));
  const d = part(r, "meal_draft").draft;
  expect(d.items[0].candidates).toEqual([]);
  const notConfigured = await J(await call(`/api/me/meal-drafts/${d.id}/items/0/web-search`, a.token, {}));
  expect(notConfigured.status).toBe("NOT_CONFIGURED");
  expect(await prisma.agentRun.count({ where: { userId: a.id, intent: "MEAL_DRAFT_ENRICHMENT" } })).toBe(0);

  const original = webSearchRef.current;
  const queries: string[] = [];
  webSearchRef.current = {
    configured: true,
    search: async (q: string) => {
      queries.push(q);
      return [
        { title: "Kandungan gizi zelvoli bakar", url: "https://gizi.example.id/zelvoli", host: "gizi.example.id", snippet: "", markdown: "Per 100 gram: Energi 150 kkal, Protein 10 g, Lemak 5 g, Karbohidrat 16 g" },
        { title: "Resep ayam goreng", url: "https://resep.example.id/ayam", host: "resep.example.id", snippet: "", markdown: "Per 100 gram: Energi 250 kkal, Protein 20 g, Lemak 18 g, Karbohidrat 1 g" },
        { title: "Zelvoli bakar porsi besar", url: "https://lain.example.id/z", host: "lain.example.id", snippet: "", markdown: "Per porsi: Energi 600 kkal" },
      ];
    },
  };
  try {
    const out = await mealDraftService.webLookup(a.id, d.id, 0);
    expect(out.status).toBe("FOUND");
    expect(queries).toEqual(["zelvoli bakar kandungan gizi per 100 gram"]);
    const item = out.draft.items[0]!;
    expect(item.candidates).toHaveLength(1);
    expect(item.candidates[0]).toMatchObject({ kind: "WEB", host: "gizi.example.id", source: "Web: gizi.example.id", per100g: { calories: 150, protein: 10, fat: 5, carbohydrates: 16, fiber: null } });
    expect(item.selected).toBeNull();
    expect(out.draft.version).toBe(2);
    const again = await mealDraftService.webLookup(a.id, d.id, 0);
    expect(again.status).toBe("FOUND");
    expect(queries).toHaveLength(1);
  } finally {
    webSearchRef.current = original;
  }
  const run = await prisma.agentRun.findFirstOrThrow({ where: { userId: a.id, intent: "MEAL_DRAFT_ENRICHMENT" } });
  expect(run.status).toBe("COMPLETED");
  expect(await prisma.agentToolCall.count({ where: { runId: run.id, tool: "search_web_nutrition", status: "OK" } })).toBe(1);
  expect(await prisma.auditEvent.count({ where: { userId: a.id, eventType: "meal_draft_web_lookup" } })).toBe(1);

  const fresh = await J(await call(`/api/me/meal-drafts/${d.id}`, a.token));
  const key = fresh.items[0].candidates[0].key;
  const saved = await J(await call(`/api/me/meal-drafts/${d.id}/confirm`, a.token, { expectedVersion: fresh.version, category: fresh.category, consumedAt: fresh.consumedAt, items: [{ index: 0, candidateKey: key, name: "zelvoli bakar", quantity: 1, unit: "portion", grams: 200 }] }));
  const meal = await J(await call(`/api/me/meals/${saved.mealId}`, a.token));
  expect(meal.items[0]).toMatchObject({ name: "Zelvoli bakar", source: "Web: gizi.example.id" });
  expect(meal.items[0].nutrition.calories).toBe(300);
});

test("Alat web tidak boleh dipakai tanpa consent kesehatan atau dari maksud lain", async () => {
  const { executeTool, ToolError } = await import("../../src/features/agent/agent.tools.ts");
  const a = await actor(["personalized_ai"]);
  const run = await prisma.agentRun.create({ data: { userId: a.id, status: "RUNNING", intent: "NUTRITION_ALTERNATIVES", inputText: "x", idempotencyKey: `k-${crypto.randomUUID()}`, expiresAt: new Date(Date.now() + 3_600_000) } });
  const code = async (intent: string) => {
    try {
      await executeTool({ userId: a.id, runId: run.id, intent, maxCalls: 2, callsUsed: 0 }, "search_web_nutrition", { query: "lalapan" });
      return "OK";
    } catch (e) {
      return e instanceof ToolError ? e.code : "OTHER";
    }
  };
  expect(await code("NUTRITION_ALTERNATIVES")).toBe("INTENT_NOT_ALLOWED");
  expect(await code("MEAL_DRAFT_ENRICHMENT")).toBe("PERMISSION_DENIED");
});
