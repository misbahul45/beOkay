import { afterAll, beforeAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { outbox } from "../../src/infrastructure/queue/outbox.ts";
import { eventHandlers } from "../../src/features/events/handlers.ts";
import { featureFlags } from "../../src/features/feature-flags/feature-flags.service.ts";
import { knowledgeService } from "../../src/features/knowledge/knowledge.service.ts";
import { llmPlannerRef, type LlmPlanner } from "../../src/features/agent/skills/llm-planner.ts";
import { runSkill } from "../../src/features/agent/skills/runner.ts";
import { skillById } from "../../src/features/agent/skills/registry.ts";
import { actors, call, J, requireIsolatedApi, todayWib, wib } from "../support/api.ts";

const { actor, cleanup } = actors();
const H = ["health_data_processing", "descriptive_summaries"];
const ALL = [...H, "personalized_ai"];
const daysAgo = (n: number) => new Date(Date.parse(todayWib() + "T00:00:00Z") - n * 86_400_000).toISOString().slice(0, 10);
const activity = (token: string, startedAt: Date, durationMinutes: number) => call("/api/me/activities", token, { id: crypto.randomUUID(), activityType: "walking", startedAt: startedAt.toISOString(), durationMinutes, reportedIntensity: "light" });
const settle = async (userId: string) => {
  for (let i = 0; i < 30 && (await prisma.outboxEvent.count({ where: { userId, status: "PENDING" } })) > 0; i++) {
    await prisma.outboxEvent.updateMany({ where: { userId, status: "PENDING" }, data: { availableAt: new Date(Date.now() - 1000) } });
    await outbox.drain(eventHandlers(), 200, userId);
    await Bun.sleep(20);
  }
};
const communities: string[] = [];

beforeAll(async () => {
  requireIsolatedApi();
  await knowledgeService.sync();
});
afterAll(async () => {
  await prisma.community.deleteMany({ where: { id: { in: communities } } });
  await featureFlags.clear("react_llm_planner", "test-suite").catch(() => {});
  await cleanup();
});

test("Check-in energi: satu per hari, koreksi berversi, terbit sebagai peristiwa, tampil di langkah berikutnya", async () => {
  const a = await actor(H);
  expect((await J(await call("/api/me/checkins/today", a.token))).checkin).toBeNull();
  const first = await J(await call("/api/me/checkins/energy", a.token, { energy: "LOW" }, "PUT"));
  expect(first.checkin).toMatchObject({ energy: "LOW", version: 1, localDate: todayWib() });
  await call("/api/me/checkins/energy", a.token, { energy: "LOW" }, "PUT");
  const second = await J(await call("/api/me/checkins/energy", a.token, { energy: "OK" }, "PUT"));
  expect(second.checkin).toMatchObject({ energy: "OK", version: 2 });
  expect(await prisma.dailyCheckin.count({ where: { userId: a.id } })).toBe(1);
  const events = await prisma.outboxEvent.findMany({ where: { userId: a.id, type: { startsWith: "record." } }, orderBy: { createdAt: "asc" } });
  expect(events.map((e) => [e.type, (e.payload as any).kind, e.revision])).toEqual([["record.created", "energy_checkin", 1], ["record.corrected", "energy_checkin", 2]]);
  expect((await call("/api/me/checkins/energy", a.token, { energy: "TIRED" }, "PUT")).status).toBe(400);
  expect((await J(await call("/api/me/today/next-action", a.token))).energy).toBe("OK");
  const b = await actor([]);
  expect((await call("/api/me/checkins/energy", b.token, { energy: "LOW" }, "PUT")).status).toBe(403);
});

test("Memori turunan: rutinitas pagi diusulkan dari catatan, selalu usulan, tidak diulang setelah ditolak", async () => {
  const a = await actor(ALL);
  for (const d of [1, 2, 3]) await activity(a.token, wib(daysAgo(d), 6, 30), 20);
  await settle(a.id);
  expect(await prisma.memoryItem.count({ where: { userId: a.id, sourceType: "DERIVED" } })).toBe(0);
  await activity(a.token, wib(daysAgo(4), 7), 15);
  await activity(a.token, wib(daysAgo(5), 19), 15);
  await settle(a.id);
  const m = await prisma.memoryItem.findFirstOrThrow({ where: { userId: a.id, sourceType: "DERIVED" } });
  expect(m).toMatchObject({ status: "PROPOSED", kind: "ACTIVITY_TIME", memoryType: "DERIVED", confidence: "INFERRED", content: "Lebih suka beraktivitas pagi hari" });
  expect(m.sourceIds.length).toBe(4);
  const list = await J(await call("/api/me/memories", a.token));
  expect(list.proposals.map((p: any) => p.id)).toEqual([m.id]);
  expect((await prisma.memoryRevision.findFirstOrThrow({ where: { memoryId: m.id } })).reason).toContain("4 dari 5 sesi");
  expect((await call(`/api/me/memories/${m.id}/dismiss`, a.token, {})).status).toBe(200);
  await activity(a.token, wib(daysAgo(6), 6), 20);
  await settle(a.id);
  expect(await prisma.memoryItem.count({ where: { userId: a.id, sourceType: "DERIVED", status: "PROPOSED" } })).toBe(0);
  const noConsent = await actor(H);
  for (const d of [1, 2, 3, 4]) await activity(noConsent.token, wib(daysAgo(d), 6), 20);
  await settle(noConsent.id);
  expect(await prisma.memoryItem.count({ where: { userId: noConsent.id } })).toBe(0);
});

test("Misi tim: agregat tim hanya tampil dengan minimal 5 anggota; tanpa kontribusi per orang", async () => {
  const purposes = [...H, "community_membership", "challenge_participation"];
  const region = (await prisma.region.findFirstOrThrow()).code;
  const community = await prisma.community.create({ data: { regionCode: region, name: `Uji tim ${crypto.randomUUID().slice(0, 6)}`, description: "uji" } });
  communities.push(community.id);
  const startsOn = new Date(daysAgo(3) + "T00:00:00Z"), endsOn = new Date(daysAgo(-3) + "T00:00:00Z");
  const team = await prisma.challenge.create({ data: { communityId: community.id, title: "Misi tim uji", description: "uji", kind: "TEAM_ACTIVE_DAYS", startsOn, endsOn, targetDays: 3, teamTargetDays: 6, scoringVersion: "score-v1", status: "OPEN" } });
  const members = [];
  for (let i = 0; i < 5; i++) {
    const u = await actor(purposes);
    members.push(u);
    await prisma.communityMembership.create({ data: { userId: u.id, communityId: community.id, alias: `Anggota ${i}`, aliasKey: `anggota-${i}-${u.id.slice(0, 4)}`, status: "ACTIVE" } });
    await prisma.challengeParticipant.create({ data: { challengeId: team.id, userId: u.id } });
  }
  await activity(members[0]!.token, wib(daysAgo(1), 7), 20);
  await activity(members[0]!.token, wib(daysAgo(2), 7), 20);
  await activity(members[1]!.token, wib(daysAgo(1), 7), 12);
  await activity(members[2]!.token, wib(daysAgo(1), 7), 5);
  const view = await J(await call(`/api/me/challenges/${team.id}/team`, members[3]!.token));
  expect(view).toMatchObject({ visible: true, teamActiveDays: 3, contributors: 2, participants: 5, teamTargetDays: 6, reached: false });
  expect(JSON.stringify(view)).not.toMatch(/Anggota|alias|userId|glucose/);
  await prisma.challengeParticipant.updateMany({ where: { challengeId: team.id, userId: members[4]!.id }, data: { leftAt: new Date() } });
  expect(await J(await call(`/api/me/challenges/${team.id}/team`, members[0]!.token))).toMatchObject({ visible: false, teamActiveDays: null, participants: 4 });
  const outsider = await actor(purposes);
  expect((await call(`/api/me/challenges/${team.id}/team`, outsider.token)).status).toBe(403);
  const regular = await prisma.challenge.create({ data: { communityId: community.id, title: "Biasa", description: "uji", kind: "ACTIVE_DAYS", startsOn, endsOn, targetDays: 3, scoringVersion: "score-v1", status: "OPEN" } });
  expect((await call(`/api/me/challenges/${regular.id}/team`, members[0]!.token)).status).toBe(404);
  const bad = await prisma.challenge.create({ data: { communityId: community.id, title: "x", description: "x", kind: "TEAM_ACTIVE_DAYS", startsOn, endsOn, targetDays: 3, scoringVersion: "score-v1", status: "OPEN" } }).then(() => "created", () => "rejected");
  expect(bad).toBe("rejected");
});

test("Perencana LLM bayangan: usulan dicatat dan dibandingkan, tidak pernah dijalankan; mati secara bawaan", async () => {
  const a = await actor(ALL);
  await call("/api/me/profile", a.token, { birthYear: 1985 }, "PATCH");
  await call("/api/me/health-profile", a.token, { diagnosisStatus: "not_diagnosed", riskStatement: "at_risk_told" }, "PUT");
  const skill = skillById("prevention.education")!;
  const saved = llmPlannerRef.current;
  const calls: string[] = [];
  const fake: LlmPlanner = { configured: true, propose: async (i) => { calls.push(i.skillId); return i.iteration === 1 ? { tool: "search_knowledge", reason: "cari bacaan", latencyMs: 3, status: "OK" } : { tool: null, reason: null, latencyMs: 0, status: "REJECTED", detail: "TOOL_NOT_ALLOWED" }; } };
  try {
    llmPlannerRef.current = fake;
    featureFlags.resetCache();
    const off = await runSkill({ userId: a.id, skill, text: "gimana cara mencegah diabetes", idempotencyKey: crypto.randomUUID(), journey: "PREVENTION" });
    expect(calls).toEqual([]);
    await featureFlags.set("react_llm_planner", true, "test-suite", null);
    featureFlags.resetCache();
    const on = await runSkill({ userId: a.id, skill, text: "gimana cara mencegah diabetes", idempotencyKey: crypto.randomUUID(), journey: "PREVENTION" });
    expect(calls.length).toBeGreaterThanOrEqual(1);
    expect(on.fsm.toolCalls).toBe(off.fsm.toolCalls);
    expect(on.blocks).toEqual(off.blocks);
    const shadow = await prisma.agentRunEvent.findMany({ where: { runId: on.runId, type: "LLM_PLAN_SHADOW" }, orderBy: { seq: "asc" } });
    expect(shadow[0]!.payload).toMatchObject({ executed: false, iteration: 1, deterministic: "search_knowledge", proposed: "search_knowledge", agree: true, status: "OK" });
    expect(await prisma.agentToolCall.count({ where: { runId: on.runId } })).toBe(on.fsm.toolCalls);
  } finally {
    llmPlannerRef.current = saved;
    await featureFlags.clear("react_llm_planner", "test-suite");
    featureFlags.resetCache();
  }
});
