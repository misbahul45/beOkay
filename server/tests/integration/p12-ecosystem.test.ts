import { afterAll, beforeAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { outbox } from "../../src/infrastructure/queue/outbox.ts";
import { eventHandlers, subscriptions } from "../../src/features/events/handlers.ts";
import { dailyFacts } from "../../src/features/projections/daily-facts.service.ts";
import { featureFlags } from "../../src/features/feature-flags/feature-flags.service.ts";
import { knowledgeService } from "../../src/features/knowledge/knowledge.service.ts";
import { executeTool, ToolError } from "../../src/features/agent/agent.tools.ts";
import { actors, call, J, requireIsolatedApi, todayWib, wib } from "../support/api.ts";

const { actor, cleanup } = actors();
const H = ["health_data_processing", "descriptive_summaries"];
const ALL = [...H, "personalized_ai", "device_data_coaching"];
const say = (token: string, thread: string, text: string) => call(`/api/me/conversations/${thread}/messages`, token, { clientMessageId: crypto.randomUUID(), text });
const daysAgo = (n: number) => new Date(Date.parse(todayWib() + "T00:00:00Z") - n * 86_400_000).toISOString().slice(0, 10);

async function withJourney(purposes: string[], body: Record<string, unknown>, birthYear = 1985) {
  const a = await actor(purposes);
  await call("/api/me/profile", a.token, { birthYear }, "PATCH");
  const r = await call("/api/me/health-profile", a.token, body, "PUT");
  expect(r.status).toBe(200);
  return { ...a, profile: await J(r) };
}
const activity = (token: string, startedAt: Date, durationMinutes: number, id = crypto.randomUUID()) =>
  call("/api/me/activities", token, { id, activityType: "walking", startedAt: startedAt.toISOString(), durationMinutes, reportedIntensity: "light" });

beforeAll(async () => {
  requireIsolatedApi();
  await knowledgeService.sync();
});
afterAll(async () => {
  await featureFlags.clear("projection_consumers", "test-suite").catch(() => {});
  await featureFlags.clear("skill_registry", "test-suite").catch(() => {});
  await cleanup();
});

test("C2 kohort: jalur dari pernyataan pengguna, peristiwa journey.changed, edukasi terpisah per jalur", async () => {
  const prev = await withJourney(H, { diagnosisStatus: "not_diagnosed", riskStatement: "prediabetes_told" });
  expect(prev.profile.journey).toMatchObject({ value: "PREVENTION", label: "Pencegahan", source: "user_statement" });
  const t2 = await withJourney(H, { diagnosisStatus: "diagnosed", diabetesType: "type_2" });
  expect(t2.profile.journey.value).toBe("T2DM_SUPPORT");
  const t1 = await withJourney(H, { diagnosisStatus: "diagnosed", diabetesType: "type_1" });
  expect(t1.profile.journey.value).toBe("UNDETERMINED");
  const well = await withJourney(H, { diagnosisStatus: "not_diagnosed" });
  expect(well.profile.journey.value).toBe("WELLNESS");
  const bad = await call("/api/me/health-profile", t2.token, { diagnosisStatus: "diagnosed", diabetesType: "type_2", riskStatement: "prediabetes_told" }, "PUT");
  expect(bad.status).toBe(422);

  const ev = await prisma.outboxEvent.findMany({ where: { userId: prev.id, type: "journey.changed" } });
  expect(ev).toHaveLength(1);
  expect(ev[0]!.payload).toMatchObject({ from: null, to: "PREVENTION", reason: "CLINICIAN_RISK_STATEMENT_REPORTED" });
  expect(await J(await call("/api/me/health-profile", prev.token, { riskStatement: "none" }, "PATCH"))).toMatchObject({ journey: { value: "WELLNESS" } });
  expect(await prisma.outboxEvent.count({ where: { userId: prev.id, type: "journey.changed" } })).toBe(2);

  const keys = async (token: string) => (await J(await call("/api/education/modules", token))).items.map((i: any) => i.key);
  const pk = await keys(prev.token), tk = await keys(t2.token), wk = await keys(well.token);
  expect(tk).toContain("hipoglikemia");
  expect(tk).not.toContain("cegah-diabetes");
  for (const k of ["hipoglikemia", "obat-bertanya-dokter", "cek-gula-mandiri", "mengenal-dmt2"]) {
    expect(pk).not.toContain(k);
    expect(wk).not.toContain(k);
  }
  expect(wk).toContain("pemeriksaan-rutin");
  expect((await call("/api/education/modules/hipoglikemia", well.token)).status).toBe(404);
});

test("C3 amplop: tiap catatan menerbitkan tepat satu peristiwa dalam transaksi yang sama; ulangan idempoten; koreksi dan arsip berversi", async () => {
  const a = await actor(H);
  const id = crypto.randomUUID();
  expect((await activity(a.token, wib(daysAgo(1), 7), 20, id)).status).toBe(201);
  expect((await activity(a.token, wib(daysAgo(1), 7), 20, id)).status).toBe(201);
  const created = await prisma.outboxEvent.findMany({ where: { userId: a.id, type: "record.created" } });
  expect(created).toHaveLength(1);
  expect(created[0]).toMatchObject({ source: "manual", sourceRecordId: id, revision: 1, timezone: "Asia/Jakarta", consentScope: "health_data_processing", quality: "user_reported", schemaVersion: 1 });
  expect(created[0]!.occurredAt!.toISOString()).toBe(wib(daysAgo(1), 7).toISOString());
  expect(created[0]!.payload).toEqual({ kind: "activity", recordId: id, localDates: [daysAgo(1)] });

  const moved = await call(`/api/me/activities/${id}`, a.token, { expectedVersion: 1, reason: "Salah tanggal", startedAt: wib(daysAgo(3), 7).toISOString() }, "PATCH");
  expect(moved.status).toBe(200);
  const corrected = await prisma.outboxEvent.findFirstOrThrow({ where: { userId: a.id, type: "record.corrected" } });
  expect(corrected).toMatchObject({ revision: 2 });
  expect((corrected.payload as any).localDates).toEqual([daysAgo(3), daysAgo(1)]);
  expect((await call(`/api/me/activities/${id}`, a.token, { expectedVersion: 2, reason: "Bukan aktivitas", archived: true }, "PATCH")).status).toBe(200);
  expect(await prisma.outboxEvent.count({ where: { userId: a.id, type: "record.archived", revision: 3 } })).toBe(1);

  const meal = await call("/api/me/meals", a.token, { id: crypto.randomUUID(), category: "lunch", consumedAt: wib(daysAgo(1), 12).toISOString(), items: [{ name: "nasi", quantity: 1, unit: "portion" }] });
  expect(meal.status).toBe(201);
  const glucose = await call("/api/me/glucose", a.token, { id: crypto.randomUUID(), originalValue: 110, originalUnit: "mg/dL", measuredAt: wib(daysAgo(1), 6).toISOString(), mealContext: "fasting" });
  expect(glucose.status).toBe(201);
  const kinds = (await prisma.outboxEvent.findMany({ where: { userId: a.id, type: "record.created" } })).map((e) => (e.payload as any).kind).sort();
  expect(kinds).toEqual(["activity", "glucose", "meal"]);
});

test("C3/C4 proyeksi: dibangun dari catatan, ditandai kotor oleh peristiwa, putar ulang identik, dan sinkron terlambat menghitung ulang", async () => {
  const a = await actor(H);
  await activity(a.token, wib(daysAgo(2), 6), 25);
  await activity(a.token, wib(daysAgo(2), 18), 5);
  const first = await dailyFacts.list(a.id, daysAgo(3), daysAgo(0), "Asia/Jakarta");
  expect(first.find((f) => f.localDate === daysAgo(2))).toMatchObject({ activeMinutes: 30, sessionCount: 2, longestSessionMinutes: 25, steps: null, sleepMinutes: null });
  expect(await prisma.dailyBehaviorFact.count({ where: { userId: a.id } })).toBe(4);

  await activity(a.token, wib(daysAgo(2), 20), 15);
  expect((await prisma.dailyBehaviorFact.findFirstOrThrow({ where: { userId: a.id, localDate: new Date(daysAgo(2) + "T00:00:00Z") } })).dirty).toBe(true);
  expect((await dailyFacts.list(a.id, daysAgo(2), daysAgo(2), "Asia/Jakarta"))[0]).toMatchObject({ activeMinutes: 45, sessionCount: 3 });

  await prisma.dailyBehaviorFact.updateMany({ where: { userId: a.id }, data: { dirty: true } });
  const stored = await dailyFacts.stored(a.id, daysAgo(3), daysAgo(0));
  await prisma.dailyBehaviorFact.deleteMany({ where: { userId: a.id } });
  const replay = await dailyFacts.list(a.id, daysAgo(3), daysAgo(0), "Asia/Jakarta");
  expect(replay).toEqual(stored);

  await call("/api/me/device-import/preferences", a.token, { steps: true }, "PATCH");
  expect((await call("/api/me/device-import", a.token, { source: "health_connect", steps: [{ localDate: daysAgo(2), steps: 4321, dataOrigin: "com.google.android.apps.fitness" }] })).status).toBe(200);
  const late = await prisma.outboxEvent.findFirstOrThrow({ where: { userId: a.id, type: "record.created", source: "health_connect" } });
  expect(late.provenance).toEqual({ dataOrigin: "com.google.android.apps.fitness" });
  expect((await dailyFacts.list(a.id, daysAgo(2), daysAgo(2), "Asia/Jakarta"))[0]!.steps).toBe(4321);
  expect(await prisma.outboxEvent.count({ where: { userId: a.id, type: "device.imported" } })).toBe(1);

  for (let i = 0; i < 40 && (await prisma.outboxEvent.count({ where: { userId: a.id, status: { not: "DONE" } } })) > 0; i++) {
    await prisma.outboxEvent.updateMany({ where: { userId: a.id, status: "PENDING" }, data: { availableAt: new Date(Date.now() - 1000) } });
    await outbox.drain(eventHandlers(), 200, a.id);
    await Bun.sleep(50);
  }
  expect(await prisma.outboxEvent.findMany({ where: { userId: a.id, status: { not: "DONE" } }, select: { type: true, lastError: true } })).toEqual([]);
  const subs = subscriptions();
  expect(subs["record.created"]).toEqual(expect.arrayContaining(["projections.daily_facts", "agent.outcome_reconcile"]));
  expect(subs["consent.withdrawn"]).toBeUndefined();
});

test("C4 paritas konsumen: hari aktif tantangan dan konteks coaching sama dengan perhitungan lama", async () => {
  const a = await actor(ALL);
  for (const [d, m] of [[1, 12], [2, 9], [3, 30], [5, 10]] as const) await activity(a.token, wib(daysAgo(d), 7), m);
  const run = async () => {
    const facts = await executeTool<any>({ userId: a.id, runId: (await prisma.agentRun.create({ data: { userId: a.id, status: "RUNNING", intent: "TREND_EXPLAIN", inputText: "x", idempotencyKey: crypto.randomUUID(), expiresAt: new Date(Date.now() + 60000) } })).id, intent: "TREND_EXPLAIN", maxCalls: 8, callsUsed: 0 }, "get_daily_facts", { days: 7 });
    return facts.days.filter((d: any) => d.activeMinutes > 0).map((d: any) => d.date);
  };
  const viaProjection = await run();
  expect(viaProjection).toEqual([daysAgo(5), daysAgo(3), daysAgo(2), daysAgo(1)]);
  await call("/api/me/meals", a.token, { id: crypto.randomUUID(), category: "dinner", consumedAt: wib(daysAgo(2), 19).toISOString(), items: [{ name: "nasi", quantity: 1, unit: "portion" }] });
  const { gatherFacts } = await import("../../src/features/coaching/coaching.service.ts");
  const now = new Date();
  const viaFacts = await gatherFacts(a.id, "Asia/Jakarta", todayWib(), now);
  await featureFlags.set("projection_consumers", false, "test-suite", null);
  featureFlags.resetCache();
  const legacy = await gatherFacts(a.id, "Asia/Jakarta", todayWib(), now);
  expect(viaFacts.recordedDays7).toBe(legacy.recordedDays7);
  expect(viaFacts.longestSessionMinutes).toBe(legacy.longestSessionMinutes);
  expect(Object.fromEntries(Object.entries(viaFacts.mealsByDay).map(([k, v]) => [k, [...v].sort()]))).toEqual(Object.fromEntries(Object.entries(legacy.mealsByDay).map(([k, v]) => [k, [...v].sort()])));
  expect(viaFacts.recordedDays7).toBe(4);
  expect(viaFacts.longestSessionMinutes).toBe(30);
  await featureFlags.clear("projection_consumers", "test-suite");
  featureFlags.resetCache();
});

test("C9 pencabutan consent: peristiwa terbit, usulan ingatan ditolak, ingatan aktif dijeda, rencana usulan kedaluwarsa, tanpa menunggu dibaca", async () => {
  const a = await actor(ALL);
  const t = crypto.randomUUID();
  await say(a.token, t, "aku biasanya jalan pagi jam 6");
  const proposals = await prisma.memoryItem.findMany({ where: { userId: a.id, status: "PROPOSED" } });
  expect(proposals.length).toBeGreaterThan(0);
  expect((await call(`/api/me/memories/${proposals[0]!.id}/confirm`, a.token, {})).status).toBe(200);
  await say(a.token, t, "aku cuma punya waktu 15 menit");
  expect(await prisma.memoryItem.count({ where: { userId: a.id, status: "PROPOSED" } })).toBeGreaterThan(0);

  expect((await call("/api/me/consents/withdraw", a.token, { purposes: ["personalized_ai"] })).status).toBe(200);
  expect(await prisma.outboxEvent.count({ where: { userId: a.id, type: "consent.withdrawn", consentScope: "personalized_ai" } })).toBe(1);
  expect(await prisma.memoryItem.count({ where: { userId: a.id, status: "PROPOSED" } })).toBe(0);
  const active = await prisma.memoryItem.findFirstOrThrow({ where: { userId: a.id, status: "ACTIVE" } });
  expect(active).toMatchObject({ pauseReason: "CONSENT_WITHDRAWN" });
  expect(active.pausedAt).not.toBeNull();
  const history = await prisma.memoryRevision.findMany({ where: { memoryId: active.id }, orderBy: { createdAt: "asc" } });
  expect(history.map((h) => h.change)).toEqual(expect.arrayContaining(["PROPOSED", "CONFIRMED"]));
});

test("C6 alat: terlarang, butuh konfirmasi, dan di luar skill ditolak dan dicatat bertingkat", async () => {
  const a = await actor(ALL);
  const run = await prisma.agentRun.create({ data: { userId: a.id, status: "RUNNING", intent: "SLEEP_RECOVERY", inputText: "x", idempotencyKey: crypto.randomUUID(), expiresAt: new Date(Date.now() + 60000) } });
  const ctx = { userId: a.id, runId: run.id, intent: "SLEEP_RECOVERY", maxCalls: 8, callsUsed: 0, allowedTools: ["get_daily_facts"] };
  const code = async (name: string, args: unknown = {}) => { try { await executeTool(ctx, name, args); return "OK"; } catch (e) { return e instanceof ToolError ? e.code : "OTHER"; } };
  expect(await code("change_medication")).toBe("PROHIBITED");
  expect(await code("raw_query")).toBe("PROHIBITED");
  expect(await code("save_memory")).toBe("REQUIRES_CONFIRMATION");
  expect(await code("join_challenge")).toBe("REQUIRES_CONFIRMATION");
  expect(await code("get_device_quality")).toBe("SKILL_TOOL_NOT_ALLOWED");
  expect(await code("get_daily_facts", { days: 7 })).toBe("OK");
  const rows = await prisma.agentToolCall.findMany({ where: { runId: run.id }, orderBy: { createdAt: "asc" } });
  expect(rows.map((r) => [r.errorCode, r.tier])).toEqual([["PROHIBITED", "PROHIBITED"], ["PROHIBITED", "PROHIBITED"], ["REQUIRES_CONFIRMATION", "USER_CONFIRMED"], ["REQUIRES_CONFIRMATION", "USER_CONFIRMED"], ["SKILL_TOOL_NOT_ALLOWED", "READ_ONLY"], [null, "READ_ONLY"]]);
});

test("C5/C6 percakapan: skill baru berjalan lewat FSM tercatat; jalur yang tidak cocok ditolak; jalur pencatatan saja tidak mendapat saran", async () => {
  const prev = await withJourney([...H, "personalized_ai"], { diagnosisStatus: "not_diagnosed", riskStatement: "at_risk_told" });
  const t = crypto.randomUUID();
  const edu = await J(await say(prev.token, t, "gimana cara mencegah diabetes"));
  expect(edu.assistantMessage.route).toBe("EDUCATION");
  const ep = edu.assistantMessage.parts as any[];
  expect(ep[0].text).toContain("Mencegah atau menunda diabetes tipe 2");
  expect(ep.find((p) => p.type === "evidence")).toMatchObject({ certainty: "insufficient" });
  expect(ep.find((p) => p.type === "notice")?.text).toContain("Draf");
  const run = await prisma.agentRun.findFirstOrThrow({ where: { userId: prev.id, skillId: "prevention.education" } });
  expect(run).toMatchObject({ status: "COMPLETED", fsmState: "COMPLETED", journey: "PREVENTION" });
  expect(run.iterations).toBeLessThanOrEqual(3);
  const path = (await prisma.agentRunEvent.findFirstOrThrow({ where: { runId: run.id, type: "FSM_PATH" } })).payload as any;
  expect(path.path).toEqual(["RECEIVED", "SAFETY_SCREEN", "ROUTE", "SELECT_SKILL", "PLAN", "EXECUTE_READ_TOOLS", "EVALUATE_EVIDENCE", "DRAFT_RESPONSE", "OUTPUT_GUARD", "COMPLETED"]);

  const odd = await J(await say(prev.token, t, "skrining zorblax itu apa"));
  const abstain = await prisma.agentRun.findMany({ where: { userId: prev.id, skillId: "prevention.education" }, orderBy: { createdAt: "desc" }, take: 1 });
  expect(odd.assistantMessage.route).toBe("EDUCATION");
  expect(abstain[0]!.iterations).toBe(2);

  const t2 = await withJourney([...H, "personalized_ai"], { diagnosisStatus: "diagnosed", diabetesType: "type_2" });
  const denied = await J(await say(t2.token, crypto.randomUUID(), "gimana cara mencegah diabetes"));
  expect(denied.assistantMessage.parts[0].text).toContain("jalur pencegahan");
  expect(await prisma.agentRun.count({ where: { userId: t2.id, skillId: "prevention.education" } })).toBe(0);

  const t1 = await withJourney([...H, "personalized_ai"], { diagnosisStatus: "diagnosed", diabetesType: "type_1" });
  for (const msg of ["ide olahraga 15 menit", "cari info tempe", "aku susah konsisten"]) {
    const r = await J(await say(t1.token, crypto.randomUUID(), msg));
    expect(r.assistantMessage.parts[0].text).toContain("belum tersedia untuk keadaanmu");
  }
  expect(await prisma.agentRun.count({ where: { userId: t1.id } })).toBe(0);
  const safety = await J(await say(t1.token, crypto.randomUUID(), "gula darahku 40 dan aku gemetar"));
  expect(safety.assistantMessage.route).toBe("SAFETY");

  const well = await withJourney([...H, "personalized_ai"], { diagnosisStatus: "not_diagnosed" });
  const sup = await J(await say(well.token, crypto.randomUUID(), "aku malas karena sering lupa"));
  expect(sup.assistantMessage.route).toBe("SUPPORT");
  const strat = (sup.assistantMessage.parts as any[]).find((p) => p.type === "strategy");
  expect(strat).toMatchObject({ barrier: "FORGOT" });
  expect(strat.key).not.toBe("FORGOT_VISIBLE");
  expect((sup.assistantMessage.parts as any[]).map((p) => p.type)).toEqual(expect.arrayContaining(["text", "strategy", "suggestions", "memory_proposal"]));

  await featureFlags.set("skill_registry", false, "test-suite", null);
  featureFlags.resetCache();
  const legacy = await J(await say(t1.token, crypto.randomUUID(), "aku susah konsisten"));
  expect(legacy.assistantMessage.parts[0].text).toContain("Wajar kalau naik turun");
  await featureFlags.clear("skill_registry", "test-suite");
  featureFlags.resetCache();
});

test("C8 isolasi jalur retrieval: jalur A tidak memuat strategi, jalur C tidak memuat bacaan; jalur pengguna menyaring dokumen", async () => {
  const a = await knowledgeService.retrieve({ query: "hipoglikemia gula darah rendah", lane: "A_PUBLIC_HEALTH", journey: "T2DM_SUPPORT", includeDrafts: true });
  expect(a.decision.status).toBe("ANSWER");
  expect(a.items.every((i) => i.lane === "A_PUBLIC_HEALTH" && i.slug.startsWith("edu:"))).toBe(true);
  const w = await knowledgeService.retrieve({ query: "hipoglikemia gula darah rendah", lane: "A_PUBLIC_HEALTH", journey: "WELLNESS", includeDrafts: true });
  expect(w.items.map((i) => i.slug)).not.toContain("edu:hipoglikemia@v1");
  const c = await knowledgeService.retrieve({ query: "lupa mencatat pengingat", lane: "C_BEHAVIOR_STRATEGY", journey: "WELLNESS", includeDrafts: true });
  expect(c.items.length).toBeGreaterThan(0);
  expect(c.items.every((i) => i.slug.startsWith("strategy:"))).toBe(true);
  expect(c.items.map((i) => i.slug)).not.toContain("strategy:FORGOT_VISIBLE@v1");
  const prod = await knowledgeService.retrieve({ query: "hipoglikemia gula darah rendah", lane: "A_PUBLIC_HEALTH", journey: "T2DM_SUPPORT", includeDrafts: false });
  expect(prod).toMatchObject({ decision: { status: "ABSTAIN" }, items: [], certainty: "unknown" });
  const none = await knowledgeService.retrieve({ query: "resep kue bolu pandan", lane: "A_PUBLIC_HEALTH", journey: "T2DM_SUPPORT", includeDrafts: true });
  expect(none.decision.status).toBe("ABSTAIN");
  const cols = await prisma.$queryRaw<{ column_name: string }[]>`SELECT column_name FROM information_schema.columns WHERE table_name IN ('knowledge_documents','knowledge_chunks') AND column_name = 'user_id'`;
  expect(cols).toEqual([]);
});

test("C9 memori: kontradiksi terdeteksi, jeda/lanjut tercatat, anggaran per skill, tidak bocor antarpengguna", async () => {
  const a = await actor(ALL), b = await actor(ALL);
  const t = crypto.randomUUID();
  await say(a.token, t, "aku biasanya jalan pagi jam 6");
  const p1 = await prisma.memoryItem.findFirstOrThrow({ where: { userId: a.id, status: "PROPOSED", kind: "ACTIVITY_TIME" } });
  await call(`/api/me/memories/${p1.id}/confirm`, a.token, {});
  await say(a.token, t, "aku biasanya jalan sore jam 5");
  const list = await J(await call("/api/me/memories", a.token));
  expect(list.conflicts.length).toBe(1);
  expect(list.items[0]).toMatchObject({ conflictState: "CONFLICTING", memoryType: "ROUTINE" });
  expect((await call(`/api/me/memories/${list.conflicts[0].id}/confirm`, a.token, {})).status).toBe(200);
  const after = await J(await call("/api/me/memories", a.token));
  expect(after.conflicts).toEqual([]);
  expect(after.items[0]).toMatchObject({ conflictState: "NONE" });
  expect(after.items[0].content).toContain("sore");
  const kept = after.items[0].id;
  expect((await call(`/api/me/memories/${kept}/pause`, a.token, {})).status).toBe(200);
  expect((await J(await call("/api/me/memories", a.token))).paused.map((m: any) => m.id)).toEqual([kept]);
  expect((await call(`/api/me/memories/${kept}/pause`, b.token, {})).status).toBe(404);
  expect((await call(`/api/me/memories/${kept}/history`, b.token)).status).toBe(404);
  expect((await call(`/api/me/memories/${kept}/resume`, a.token, {})).status).toBe(200);
  const hist = (await J(await call(`/api/me/memories/${kept}/history`, a.token))).items.map((h: any) => h.change);
  expect(hist).toEqual(expect.arrayContaining(["PROPOSED", "CONFIRMED", "SUPERSEDED", "PAUSED", "RESUMED"]));
  expect(await prisma.outboxEvent.count({ where: { userId: a.id, type: "memory.changed" } })).toBeGreaterThanOrEqual(4);
  const { memoryService } = await import("../../src/features/memory/memory.service.ts");
  expect((await memoryService.retrieve(a.id, "activity.planner", 1)).ids).toEqual([kept]);
  expect((await memoryService.retrieve(a.id, "sleep.recovery")).withheld).toBe("SKILL_HAS_NO_MEMORY_ACCESS");
  expect((await memoryService.retrieve(b.id, "activity.planner")).ids).toEqual([]);
});
