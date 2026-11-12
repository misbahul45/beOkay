import { afterAll, beforeAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { conversationService, llmRouterRef } from "../../src/features/conversation/conversation.service.ts";
import { createLlmRouter } from "../../src/features/conversation/intent-classifier.ts";
import { featureFlags } from "../../src/features/feature-flags/feature-flags.service.ts";
import { memoryService } from "../../src/features/memory/memory.service.ts";
import { activityConstraintsFrom } from "../../src/features/memory/memory.extract.ts";
import { coachingService } from "../../src/features/coaching/coaching.service.ts";
import { J, actors, call, hash, requireIsolatedApi, todayWib, wib } from "../support/api.ts";

const { actor, cleanup } = actors();
const BASE = ["health_data_processing", "descriptive_summaries", "personalized_ai"];
const ALL = [...BASE, "ai_message_understanding"];
const original = llmRouterRef.current;
const calls = { n: 0 };
let judge: { verdict: string; category?: string } = { verdict: "SAFE" };
let classify: Record<string, unknown> = { route: "STATS", confidence: 0.9, domain: "activity" };

beforeAll(() => {
  requireIsolatedApi();
  llmRouterRef.current = createLlmRouter({
    apiKey: "test-key",
    model: "fake-model",
    fetchImpl: (async (_u: unknown, init: RequestInit) => {
      calls.n++;
      const body = JSON.parse(String(init.body));
      const content = JSON.stringify((body.messages[0].content as string).startsWith("Kamu penilai") ? judge : classify);
      return new Response(JSON.stringify({ choices: [{ message: { content } }] }), { status: 200 });
    }) as unknown as typeof fetch,
  });
});
afterAll(async () => {
  llmRouterRef.current = original;
  await prisma.featureFlag.deleteMany({});
  featureFlags.resetCache();
  await cleanup();
});

const send = async (userId: string, text: string, threadId = crypto.randomUUID()): Promise<any> => conversationService.post(userId, threadId, { clientMessageId: crypto.randomUUID(), text } as any);

test("Kebijakan consent memuat tujuan opsional baru untuk pemahaman pesan", async () => {
  const policy = await J(await call("/api/consent-policies/current"));
  expect(policy.purposes.find((p: any) => p.purpose === "ai_message_understanding")).toMatchObject({ required: false });
});

test("A-1: pesan yang tidak dikenali aturan dipahami model hanya dengan consent; usulan dicatat; penanda basis tampil", async () => {
  const a = await actor(ALL), b = await actor(BASE);
  calls.n = 0;
  judge = { verdict: "SAFE" };
  classify = { route: "STATS", confidence: 0.9, domain: "activity" };
  const out = await send(a.id, "kok aku jarang gerak ya akhir-akhir ini");
  expect(out.assistantMessage.route).toBe("STATS");
  expect(out.assistantMessage.basis.sources.map((s: any) => s.kind)).toContain("LANGUAGE_MODEL");
  const msg = await prisma.conversationMessage.findUniqueOrThrow({ where: { id: out.assistantMessage.id } });
  expect(msg.routerVersion).toBe("router-v4-hybrid");
  const prop = await prisma.routerProposal.findFirstOrThrow({ where: { userId: a.id } });
  expect(prop).toMatchObject({ decision: "ACCEPTED", proposedRoute: "STATS", judgeVerdict: "SAFE", model: "fake-model", messageId: out.userMessage.id });
  expect(calls.n).toBe(2);

  calls.n = 0;
  const plain = await send(b.id, "kok aku jarang gerak ya akhir-akhir ini");
  expect(plain.assistantMessage.route).toBe("UNKNOWN");
  expect(calls.n).toBe(0);
  expect(await prisma.routerProposal.count({ where: { userId: b.id } })).toBe(0);

  const regexFirst = await send(a.id, "bagaimana aktivitasku minggu ini?");
  expect(regexFirst.assistantMessage.route).toBe("STATS");
  expect(regexFirst.assistantMessage.basis.sources.map((s: any) => s.kind)).not.toContain("LANGUAGE_MODEL");
});

test("A-6: judge yang menahan menghasilkan kartu keselamatan; usulan ditolak tetap UNKNOWN; sakelar llm_router mematikan semuanya", async () => {
  const a = await actor(ALL);
  judge = { verdict: "HOLD", category: "MEDICAL_ADVICE" };
  const held = await send(a.id, "yang cocok buat badanku yang mana ya kak");
  expect(held.assistantMessage.route).toBe("SAFETY");
  expect(await prisma.routerProposal.findFirstOrThrow({ where: { userId: a.id } })).toMatchObject({ decision: "HELD", judgeCategory: "MEDICAL_ADVICE" });
  judge = { verdict: "SAFE" };
  classify = { route: "FOOD", confidence: 0.95, query: "rendang" };
  const rejected = await send(a.id, "kok aku jarang gerak ya akhir-akhir ini");
  expect(rejected.assistantMessage.route).toBe("UNKNOWN");
  expect(await prisma.routerProposal.findFirstOrThrow({ where: { userId: a.id }, orderBy: { createdAt: "desc" } })).toMatchObject({ decision: "REJECTED", rejectReason: "QUERY_NOT_IN_TEXT" });
  await featureFlags.set("llm_router", false, "test-suite", null);
  calls.n = 0;
  await send(a.id, "kok aku jarang gerak ya akhir-akhir ini");
  expect(calls.n).toBe(0);
  await featureFlags.clear("llm_router", "test-suite");
});

test("A-4: konteks makan, hambatan, dan kondisi sementara diusulkan dulu, punya kedaluwarsa, dan kondisi sakit membatasi aktivitas", async () => {
  const a = await actor(ALL);
  judge = { verdict: "SAFE" };
  classify = { route: "UNKNOWN", confidence: 0.2 };
  const cook = await send(a.id, "yang masak di rumah biasanya istriku");
  const memPart = cook.assistantMessage.parts.find((p: any) => p.type === "memory_proposal");
  expect(memPart).toBeTruthy();
  const proposed = await prisma.memoryItem.findUniqueOrThrow({ where: { id: memPart.memoryId } });
  expect(proposed).toMatchObject({ kind: "FOOD_CONTEXT", status: "PROPOSED", retention: "EXPIRES" });
  expect(Math.round((proposed.expiresAt!.getTime() - Date.now()) / 86_400_000)).toBe(180);
  const flu = await send(a.id, "aku lagi flu nih");
  const fluId = flu.assistantMessage.parts.find((p: any) => p.type === "memory_proposal").memoryId;
  await memoryService.confirm(a.id, fluId);
  const active = await memoryService.activeFor(a.id);
  expect(active.find((m) => m.key === "HEALTH_EVENT:UNWELL")).toMatchObject({ sensitivity: "MEDIUM" });
  expect(activityConstraintsFrom(active)).toMatchObject({ maxMinutes: 10 });
  classify = { route: "PREFERENCE", confidence: 0.9, memory: { kind: "BARRIER", content: "kerjaan kantor menumpuk tiap sore" } };
  const llmMem = await send(a.id, "kerjaan kantor menumpuk tiap sore jadi susah");
  const llmId = llmMem.assistantMessage.parts.find((p: any) => p.type === "memory_proposal")?.memoryId;
  expect(await prisma.memoryItem.findUniqueOrThrow({ where: { id: llmId } })).toMatchObject({ kind: "BARRIER", sourceType: "LANGUAGE_MODEL", confidence: "INFERRED", status: "PROPOSED" });
  await prisma.memoryItem.updateMany({ where: { userId: a.id, key: "HEALTH_EVENT:UNWELL" }, data: { expiresAt: new Date(Date.now() - 60_000) } });
  expect((await memoryService.activeFor(a.id)).some((m) => m.key === "HEALTH_EVENT:UNWELL")).toBe(false);
  expect((await J(await call("/api/me/memories", a.token))).items.some((m: any) => m.content === "Sedang kurang sehat")).toBe(false);
});

test("A-5: episode mingguan dari keputusan rencana muncul di refleksi dan menahan waktu yang sering ditolak", async () => {
  const a = await actor(BASE);
  const week = await coachingService.reflectionWeek(a.id);
  const mk = (status: string, slot: string, days = 3, decided = true) =>
    prisma.coachingAction.create({ data: { userId: a.id, opportunityKey: `T:${crypto.randomUUID()}`, source: "ACTIVITY_STEP_DOWN", kind: "ACTIVITY_SESSION", title: "Jalan kaki 10 menit", rationale: "uji", evidence: {}, params: { activityType: "walking", durationMinutes: 10 }, slot, startDate: new Date(week + "T00:00:00Z"), days, status, policyVersion: "coach-rules-v2", expiresAt: new Date(), decidedAt: decided ? wib(week, 9) : null } });
  const acc = await mk("ACCEPTED", "MORNING");
  await prisma.coachingOutcome.create({ data: { userId: a.id, actionId: acc.id, localDate: new Date(week + "T00:00:00Z"), status: "USER_CONFIRMED" } });
  await mk("DECLINED", "AFTERNOON");
  await mk("DECLINED", "AFTERNOON");
  for (let i = 0; i < 3; i++) await prisma.mealLog.create({ data: { userId: a.id, category: "lunch", consumedAt: wib(week, 12), createHash: hash() } });
  const r = await J(await call("/api/me/coaching/checkins", a.token));
  expect(r.learned.lines).toEqual(["1 dari 3 hari rencana jalan kaki pagi terlaksana.", "Rencana sore 2 kali kamu tolak, jadi aku tidak menawarkan sore dulu."]);
  expect(await prisma.weeklyEpisode.count({ where: { userId: a.id } })).toBe(1);
  const bundle = await J(await call("/api/me/export", a.token));
  expect(bundle.counts.weeklyEpisodes).toBe(1);
  expect(bundle.counts).toHaveProperty("routerProposals");
  void todayWib;
});

test("A-8: model hidangan dihentikan; skrip registrasi menolak kunci itu tanpa izin eksplisit", async () => {
  const p = Bun.spawn(["bun", "run", "scripts/ml/register-model.ts", "dish-classifier", "v9", "/nonexistent"], { stdout: "pipe", stderr: "pipe", env: process.env });
  const err = await new Response(p.stderr).text();
  expect(await p.exited).toBe(1);
  expect(err).toContain("dihentikan");
});
