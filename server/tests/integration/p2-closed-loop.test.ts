import { afterAll, beforeAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { outbox, MAX_ATTEMPTS } from "../../src/infrastructure/queue/outbox.ts";
import { outcomes } from "../../src/features/agent/outcomes.ts";
import { sweepOutcomes } from "../../src/features/agent/agent-worker.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET", headers: Record<string, string> = {}) =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}), ...headers }, body: body ? JSON.stringify(body) : undefined });
const J = async (r: Response) => (await r.json()) as any;
const ALL = ["health_data_processing", "personalized_ai", "ai_text_generation"];
async function actor(purposes: string[] = ALL) {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "Fixture", email: `cl-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  const policy = await J(await call("/api/consent-policies/current", token));
  await call("/api/me/consents", token, { policyVersion: policy.version, purposes });
  await call("/api/me/preferences", token, { timezone: "Asia/Jakarta" }, "PATCH");
  return { id, token };
}
const key = () => `k-${crypto.randomUUID()}`;
const run = (token: string, message: string, extra: object = {}, q = "") => call(`/api/me/agent/runs${q}`, token, { idempotencyKey: key(), message, ...extra });
const decide = (token: string, recId: string, decision: "ACCEPT" | "REJECT", v = 1, op: string = crypto.randomUUID()) => call(`/api/me/agent/recommendations/${recId}/decision`, token, { operationId: op, decision, expectedVersion: v });
const food = [
  ["ZZCL01", "Zelkap tempe goreng", 300, 12, 20, 18],
  ["ZZCL02", "Zelkap tahu kukus", 80, 2, 8, 5],
  ["ZZCL03", "Zelkap kacang rebus", 320, 20, 25, 14],
  ["ZZCL04", "Zelkap bayam tumis", 40, 4, 3, 2],
  ["ZZCL05", "Zelkap ikan pepes", 150, 1, 20, 7],
] as const;
beforeAll(async () => {
  for (const [code, name, cal, carb, protein, fat] of food)
    await prisma.$executeRawUnsafe(`INSERT INTO food_reference (code,name,name_normalized,source,source_version,source_ref,page,chapter,status,calories,carbohydrates,protein,fat,updated_at) VALUES ('${code}','${name}','${name.toLowerCase()}','Tabel Komposisi Pangan Indonesia','TKPI 2017','KZGMI-2001',30,'4.1. UJI','verified_auto',${cal},${carb},${protein},${fat},now())`);
});
afterAll(async () => {
  await prisma.$executeRawUnsafe(`DELETE FROM food_reference WHERE code LIKE 'ZZCL%'`);
  await prisma.users.deleteMany({ where: { id: { in: users } } });
});
const drain = () => outbox.drain(outcomes.handlers, 100);

async function acceptFirst(token: string, query = "zelkap") {
  const r = await J(await run(token, `alternatif ${query}`, { query }));
  const rec = r.recommendations[0];
  expect((await decide(token, rec.id, "ACCEPT")).status).toBe(200);
  return { run: r, rec };
}
async function logMeal(token: string, name: string, consumedAt = new Date()) {
  const res = await call("/api/me/meals", token, { id: crypto.randomUUID(), category: "lunch", consumedAt: consumedAt.toISOString(), items: [{ name, quantity: 1, unit: "portion" }] });
  expect(res.status).toBe(201);
  return (await J(res)).id as string;
}

test("Outbox: peristiwa ditulis bersama keputusan, dedupe mencegah ganda, penangan gagal di-retry lalu dead-letter", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor();
  const { rec } = await acceptFirst(a.token);
  const ev = await prisma.outboxEvent.findMany({ where: { userId: a.id } });
  expect(ev.map((e) => e.type)).toEqual(["recommendation.decided"]);
  expect(ev[0]).toMatchObject({ status: "PENDING", attempts: 0 });
  // Ulangan keputusan dengan operationId sama tidak menambah peristiwa.
  const op = crypto.randomUUID();
  const again = await J(await run(a.token, "alternatif zelkap", { query: "zelkap" }));
  const rec2 = again.recommendations[0];
  expect((await decide(a.token, rec2.id, "REJECT", 1, op)).status).toBe(200);
  expect((await decide(a.token, rec2.id, "REJECT", 1, op)).status).toBe(200);
  expect(await prisma.outboxEvent.count({ where: { userId: a.id, type: "recommendation.decided" } })).toBe(2);

  // Pengurasan: sukses → DONE.
  const r1 = await drain();
  expect(r1.done).toBeGreaterThanOrEqual(2);
  expect(await prisma.outboxEvent.count({ where: { userId: a.id, status: "PENDING" } })).toBe(0);

  // Gagal: tanpa penangan → retry dengan backoff (tidak langsung tersedia lagi), lalu dead-letter setelah MAX_ATTEMPTS.
  await outbox.enqueue(prisma, { userId: a.id, type: "tak.dikenal", dedupeKey: `x-${a.id}` });
  await outbox.enqueue(prisma, { userId: a.id, type: "tak.dikenal", dedupeKey: `x-${a.id}` }); // dedupe
  expect(await prisma.outboxEvent.count({ where: { dedupeKey: `x-${a.id}` } })).toBe(1);
  const first = await outbox.drain({}, 100);
  expect(first.failed).toBeGreaterThanOrEqual(1);
  const row = await prisma.outboxEvent.findFirstOrThrow({ where: { dedupeKey: `x-${a.id}` } });
  expect(row).toMatchObject({ status: "PENDING", attempts: 1 });
  expect(row.availableAt.getTime()).toBeGreaterThan(Date.now()); // backoff: belum tersedia lagi
  expect(row.lastError).toContain("NO_HANDLER");
  for (let i = 1; i < MAX_ATTEMPTS; i++) {
    await prisma.outboxEvent.update({ where: { id: row.id }, data: { availableAt: new Date(Date.now() - 1000) } });
    await outbox.drain({}, 100);
  }
  expect(await prisma.outboxEvent.findUniqueOrThrow({ where: { id: row.id } })).toMatchObject({ status: "DEAD", attempts: MAX_ATTEMPTS });
  expect(rec).toBeTruthy();
});

test("Outbox: dua pekerja bersamaan tidak memproses peristiwa yang sama dua kali", async () => {
  const a = await actor();
  for (let i = 0; i < 6; i++) await outbox.enqueue(prisma, { userId: a.id, type: "recommendation.feedback", dedupeKey: `par-${a.id}-${i}` });
  let handled = 0;
  const handlers = { "recommendation.feedback": async () => { handled++; await Bun.sleep(5); } };
  await Promise.all([outbox.drain(handlers, 3), outbox.drain(handlers, 3), outbox.drain(handlers, 3)]);
  expect(handled).toBeLessThanOrEqual(6);
  expect(await prisma.outboxEvent.count({ where: { userId: a.id, status: "DONE" } })).toBe(handled);
});

test("E2E-12 inti: rencana makan diterima → catatan makan nyata → hasil TERUKUR → peringkat naik dengan alasan; arsip catatan menarik hasil dan bonusnya", async () => {
  const a = await actor();
  const { rec } = await acceptFirst(a.token);
  const name: string = rec.candidate.name;
  expect((await J(await call("/api/me/planned-meals", a.token))).items[0].measuredOutcome).toBeNull(); // belum ada catatan

  const mealId = await logMeal(a.token, name);
  const list = await J(await call("/api/me/planned-meals", a.token)); // rekonsiliasi saat dibaca
  expect(list.items[0].measuredOutcome).toMatchObject({ kind: "MEAL_LOGGED" });
  const outc = await prisma.recommendationOutcome.findFirstOrThrow({ where: { userId: a.id } });
  expect(outc.evidenceType).toBe("meal_item");

  // Umpan balik yang dilaporkan sendiri tidak diperlukan: hasil terukur berdiri sendiri; personalisasi diterapkan lewat outbox.
  await drain();
  const prof = await J(await call("/api/me/personalization", a.token));
  expect(prof.likedTerms.length).toBeGreaterThan(0);
  expect(prof.rulesVersion).toBe("pref-rules-v2");
  const events = await prisma.personalizationEvent.findMany({ where: { userId: a.id } });
  expect(events.map((e) => e.reason)).toContain("OUTCOME_OBSERVED");

  // Rekonsiliasi berulang idempoten: tidak ada hasil/peristiwa ganda.
  await outcomes.reconcile(a.id);
  await drain();
  expect(await prisma.recommendationOutcome.count({ where: { userId: a.id } })).toBe(1);
  expect(await prisma.personalizationEvent.count({ where: { userId: a.id, reason: "OUTCOME_OBSERVED" } })).toBe(1);

  // Permintaan berikut: butir yang terukur dimakan mendapat bonus beralasan.
  const next = await J(await run(a.token, "alternatif zelkap", { query: "zelkap" }));
  const boosted = next.recommendations.filter((r: any) => r.explanation.includes("dinaikkan"));
  expect(boosted.length).toBeGreaterThan(0);
  expect(boosted[0].personalization.boost).toBeGreaterThan(0);

  // Koreksi: catatan diarsipkan → hasil ditarik, bonus dibatalkan.
  const meal = await J(await call(`/api/me/meals/${mealId}`, a.token));
  expect((await call(`/api/me/meals/${mealId}`, a.token, { expectedVersion: meal.version, reason: "Salah catat", archived: true }, "PATCH")).status).toBe(200);
  await outcomes.reconcile(a.id);
  await drain();
  expect(await prisma.recommendationOutcome.count({ where: { userId: a.id } })).toBe(0);
  const after = await J(await call("/api/me/personalization", a.token));
  expect(after.likedTerms).toEqual([]);
  expect((await prisma.personalizationEvent.findMany({ where: { userId: a.id } })).map((e) => e.reason)).toContain("OUTCOME_RETRACTED");
});

test("Hasil terukur aktivitas: sesi jenis sama pada tanggal rencana dengan durasi ≥ 50%; sesi yang terlalu singkat atau jenis lain tidak cocok", async () => {
  const a = await actor();
  const startedAt = (mins: number) => new Date(Date.now() - (mins + 2) * 60_000).toISOString();
  for (let d = 1; d <= 5; d++) await call("/api/me/activities", a.token, { id: crypto.randomUUID(), activityType: "walking", startedAt: new Date(Date.now() - d * 86_400_000 - 32 * 60_000).toISOString(), durationMinutes: 30 });
  const r = await J(await run(a.token, "rencana jalan kaki ringan"));
  const rec = r.recommendations[0];
  expect((await decide(a.token, rec.id, "ACCEPT")).status).toBe(200);
  const mins = rec.activity.durationMinutes;
  await call("/api/me/activities", a.token, { id: crypto.randomUUID(), activityType: "cycling", startedAt: startedAt(mins), durationMinutes: mins }); // jenis lain
  await call("/api/me/activities", a.token, { id: crypto.randomUUID(), activityType: "walking", startedAt: startedAt(2), durationMinutes: 2 }); // terlalu singkat
  expect((await outcomes.reconcile(a.id)).observed).toBe(0);
  const ok = await call("/api/me/activities", a.token, { id: crypto.randomUUID(), activityType: "walking", startedAt: startedAt(Math.ceil(mins * 0.6)), durationMinutes: Math.ceil(mins * 0.6) });
  expect(ok.status).toBe(201);
  const plans = await J(await call("/api/me/activity-plans", a.token));
  expect(plans.items[0].measuredOutcome).toMatchObject({ kind: "ACTIVITY_LOGGED" });
});

test("Rekonsiliasi hanya untuk pengguna yang masih memberi persetujuan; pekerja menyapu rencana terbuka", async () => {
  const a = await actor();
  const { rec } = await acceptFirst(a.token);
  await logMeal(a.token, rec.candidate.name);
  await call("/api/me/consents/withdraw", a.token, { purposes: ["personalized_ai"] }); // cabut
  expect(await outcomes.reconcile(a.id)).toEqual({ observed: 0, retracted: 0 });
  expect(await prisma.recommendationOutcome.count({ where: { userId: a.id } })).toBe(0);
  const b = await actor();
  const accepted = await acceptFirst(b.token);
  await logMeal(b.token, accepted.rec.candidate.name);
  const swept = await sweepOutcomes();
  expect(swept.observed).toBeGreaterThanOrEqual(1);
  expect(await prisma.recommendationOutcome.count({ where: { userId: b.id } })).toBe(1);
});

test("Multi-giliran: 'yang lain' tidak mengulang kandidat sebelumnya; 'kenapa' menjelaskan tanpa alat; run milik orang lain tidak dapat dijadikan induk", async () => {
  const a = await actor();
  const t1 = await J(await run(a.token, "alternatif zelkap", { query: "zelkap" }));
  expect(t1.turn).toBe(1);
  const names1 = t1.recommendations.map((r: any) => r.candidate.name);
  expect(names1.length).toBe(3);
  const t2 = await J(await run(a.token, "ada pilihan lain?", { previousRunId: t1.id }));
  expect(t2).toMatchObject({ turn: 2, parentRunId: t1.id });
  const names2 = t2.recommendations.map((r: any) => r.candidate.name);
  expect(names2.length).toBe(2); // lima fixture, tiga sudah ditawarkan
  for (const n of names2) expect(names1).not.toContain(n);
  const t3 = await J(await run(a.token, "ada yang lain lagi?", { previousRunId: t2.id }));
  expect(t3.status).toBe("COMPLETED");
  expect(t3.recommendations).toEqual([]);
  expect(t3.message).toContain("Tidak ada pilihan lain");
  const why = await J(await run(a.token, "kenapa itu disarankan?", { previousRunId: t1.id }));
  expect(why).toMatchObject({ status: "COMPLETED", intent: "FOLLOW_UP_WHY" });
  expect(why.message).toContain(names1[0]);
  expect(await prisma.agentToolCall.count({ where: { runId: why.id } })).toBe(0);
  const events = (await J(await call(`/api/me/agent/runs/${t2.id}`, a.token))).events.map((e: any) => e.type);
  expect(events).toContain("FOLLOW_UP");

  const b = await actor();
  expect((await run(b.token, "ada pilihan lain?", { previousRunId: t1.id })).status).toBe(404);
  expect((await run(a.token, "ada pilihan lain?", { previousRunId: crypto.randomUUID() })).status).toBe(404);
});

test("Teks LLM: tanpa kunci Mistral atau tanpa persetujuan ai_text_generation selalu templat, dan ini terlihat di respons", async () => {
  const withConsent = await actor();
  const withoutConsent = await actor(["health_data_processing", "personalized_ai"]);
  const a = await J(await run(withConsent.token, "alternatif zelkap", { query: "zelkap" }));
  const b = await J(await run(withoutConsent.token, "alternatif zelkap", { query: "zelkap" }));
  for (const r of [...a.recommendations, ...b.recommendations]) expect(r.textSource).toBe("TEMPLATE");
  expect(a.events.map((e: any) => e.type)).not.toContain("LLM_TEXT"); // API uji tidak punya kunci → tidak ada pemanggilan
});

test("Mode async + SSE: 202 segera; aliran memutar ulang peristiwa, mendukung Last-Event-ID, dan berakhir dengan state; orang lain 404", async () => {
  const a = await actor();
  const created = await run(a.token, "alternatif zelkap", { query: "zelkap" }, "?async=1");
  expect(created.status).toBe(202);
  const body = await J(created);
  const stream = await call(`/api/me/agent/runs/${body.id}/stream`, a.token);
  expect(stream.status).toBe(200);
  expect(stream.headers.get("content-type")).toContain("text/event-stream");
  const text = await stream.text(); // berakhir sendiri saat run menunggu keputusan
  expect(text).toContain("event: RUN_CREATED");
  expect(text).toContain("event: RECOMMENDATIONS_OFFERED");
  const state = JSON.parse(text.split("event: state\ndata: ")[1]!.split("\n")[0]!);
  expect(state).toMatchObject({ status: "WAITING_FOR_USER" });
  expect(state.recommendations.length).toBe(3);
  const ids = [...text.matchAll(/^id: (\d+)$/gm)].map((m) => Number(m[1]));
  expect(ids).toEqual([...ids].sort((x, y) => x - y));
  // Sambung ulang dari id terakhir: tidak ada peristiwa lama, hanya state.
  const resumed = await (await call(`/api/me/agent/runs/${body.id}/stream`, a.token, undefined, "GET", { "last-event-id": String(ids.at(-1)) })).text();
  expect(resumed).not.toContain("event: RUN_CREATED");
  expect(resumed).toContain("event: state");

  const other = await actor();
  expect((await call(`/api/me/agent/runs/${body.id}/stream`, other.token)).status).toBe(404);
  expect((await call(`/api/me/agent/runs/${body.id}/stream`)).status).toBe(401);
  // Pencabutan persetujuan: aliran tidak membocorkan saran.
  await call("/api/me/consents/withdraw", a.token, { purposes: ["personalized_ai"] });
  const revoked = await (await call(`/api/me/agent/runs/${body.id}/stream`, a.token)).text();
  const st = JSON.parse(revoked.split("event: state\ndata: ")[1]!.split("\n")[0]!);
  expect(st).toMatchObject({ status: "BLOCKED", consentRequired: true });
  expect(st.recommendations).toEqual([]);
});

test("E2E-11 (sisi server): setelah klien dimulai ulang, saran yang menunggu dapat dipulihkan; yang diputuskan, dibatalkan, atau tanpa persetujuan tidak muncul; milik orang lain tidak bocor", async () => {
  const a = await actor();
  const r1 = await J(await run(a.token, "alternatif zelkap", { query: "zelkap" }));
  const r2 = await J(await run(a.token, "ada pilihan lain?", { previousRunId: r1.id }));
  const pending = await J(await call("/api/me/agent/pending", a.token));
  expect(pending.items.map((x: any) => x.id)).toEqual([r1.id, r2.id]); // kronologis
  expect(pending.items[0].recommendations.length).toBe(3);
  expect(pending.items[0].recommendations[0].status).toBe("OFFERED");
  // Diputuskan semua → run selesai → tidak lagi menunggu.
  for (const rec of r2.recommendations) expect((await decide(a.token, rec.id, "REJECT")).status).toBe(200);
  expect((await J(await call("/api/me/agent/pending", a.token))).items.map((x: any) => x.id)).toEqual([r1.id]);
  await call(`/api/me/agent/runs/${r1.id}/cancel`, a.token, {});
  expect((await J(await call("/api/me/agent/pending", a.token))).items).toEqual([]);

  const b = await actor();
  await run(b.token, "alternatif zelkap", { query: "zelkap" });
  expect((await J(await call("/api/me/agent/pending", a.token))).items).toEqual([]); // milik b tidak terlihat oleh a
  await call("/api/me/consents/withdraw", b.token, { purposes: ["personalized_ai"] });
  expect(await J(await call("/api/me/agent/pending", b.token))).toEqual({ items: [], consentRequired: true });
  expect((await call("/api/me/agent/pending")).status).toBe(401);
});
