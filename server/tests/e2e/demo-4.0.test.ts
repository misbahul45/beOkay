import { afterAll, beforeAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { outbox } from "../../src/infrastructure/queue/outbox.ts";
import { eventHandlers } from "../../src/features/events/handlers.ts";
import { knowledgeService } from "../../src/features/knowledge/knowledge.service.ts";
import { executeTool, ToolError, webSearchRef } from "../../src/features/agent/agent.tools.ts";
import { actors, call, J, requireIsolatedApi } from "../support/api.ts";

const { actor, cleanup } = actors();
const PURPOSES = ["health_data_processing", "descriptive_summaries", "personalized_ai", "device_data_coaching"];
const say = async (token: string, thread: string, text: string) => (await J(await call(`/api/me/conversations/${thread}/messages`, token, { clientMessageId: crypto.randomUUID(), text }))).assistantMessage;
const settle = async (userId: string) => {
  for (let i = 0; i < 30 && (await prisma.outboxEvent.count({ where: { userId, status: "PENDING" } })) > 0; i++) {
    await prisma.outboxEvent.updateMany({ where: { userId, status: "PENDING" }, data: { availableAt: new Date(Date.now() - 1000) } });
    await outbox.drain(eventHandlers(), 200, userId);
    await Bun.sleep(30);
  }
};

beforeAll(async () => {
  requireIsolatedApi();
  await knowledgeService.sync();
});
afterAll(cleanup);

test("Demo 4.0: sepuluh langkah dari pendaftaran sampai saran yang berubah karena ingatan", async () => {
  const u = await actor(PURPOSES);
  const thread = crypto.randomUUID();

  expect((await call("/api/me/profile", u.token, { birthYear: 1988 }, "PATCH")).status).toBe(200);
  const hp = await J(await call("/api/me/health-profile", u.token, { diagnosisStatus: "not_diagnosed", riskStatement: "prediabetes_told" }, "PUT"));
  expect(hp.journey.value).toBe("PREVENTION");

  const first = await J(await call("/api/me/today/next-action", u.token));
  expect(first).toMatchObject({ journey: "PREVENTION", flow: ["TODAY", "NEXT_ACTION", "CONFIRM", "PROGRESS", "REFLECTION", "INSIGHTS", "CHALLENGES"] });
  expect(["LOG_SOMETHING", "WEEKLY_REFLECTION"]).toContain(first.action.kind);

  const offer = await say(u.token, thread, "ide olahraga ringan 10 menit");
  expect(offer.route).toBe("ACTIVITY_PLAN");
  const recPart = offer.parts.find((p: any) => p.type === "recommendations");
  expect(recPart.kind).toBe("ACTIVITY");
  const recId = recPart.recommendationIds[0];
  const waiting = await J(await call("/api/me/today/next-action", u.token));
  expect(waiting.action).toMatchObject({ kind: "CONFIRM_RECOMMENDATION", spark: "AWAITING_CONFIRMATION", step: "CONFIRM", ref: recId });

  const op = crypto.randomUUID();
  const dec = await J(await call(`/api/me/agent/recommendations/${recId}/decision`, u.token, { operationId: op, decision: "ACCEPT", expectedVersion: 1 }));
  expect(dec.activityPlanId).toBeTruthy();
  const rec = await prisma.recommendation.findUniqueOrThrow({ where: { id: recId } });
  const fsm = await prisma.agentRunEvent.findFirstOrThrow({ where: { runId: rec.runId, type: "FSM_DECISION" } });
  expect((fsm.payload as any).path).toEqual(["EXECUTE_AUTHORIZED_ACTION", "OBSERVE_OUTCOME", "COMPLETED"]);
  expect((fsm.payload as any).receipt).toBe(op);
  const plan = await prisma.activityPlan.findUniqueOrThrow({ where: { id: dec.activityPlanId } });

  await call("/api/me/device-import/preferences", u.token, { workouts: true, steps: true, sleep: true }, "PATCH");
  const started = new Date(Date.now() - 40 * 60_000);
  const imp = await J(await call("/api/me/activities/import", u.token, { source: "health_connect", sessions: [{ externalId: "hc-walk-1", activityType: plan.activityType, startedAt: started.toISOString(), durationMinutes: plan.durationMinutes, dataOrigin: "com.samsung.android.wear.shealth", recordingMethod: "active", device: "watch" }] }));
  expect(imp.summary.created).toBe(1);
  await settle(u.id);
  const outcome = await prisma.recommendationOutcome.findFirst({ where: { userId: u.id, recommendationId: recId } });
  expect(outcome).toMatchObject({ kind: "ACTIVITY_LOGGED", evidenceType: "activity_session" });

  const progress = await J(await call("/api/me/today/next-action", u.token));
  expect(progress.progress.week.activeDays).toBeGreaterThanOrEqual(1);
  expect(progress.progress.week.deviceDays).toBeGreaterThanOrEqual(1);
  const devices = await J(await call("/api/me/devices/status", u.token));
  expect(devices.signals.find((s: any) => s.signal === "workouts").observedDays).toBeGreaterThanOrEqual(1);
  expect(devices.origins).toContain("com.samsung.android.wear.shealth");

  const reflect = await say(u.token, thread, "ayo refleksi");
  expect(reflect.route).toBe("REFLECTION");

  const mem = await say(u.token, thread, "aku biasanya jalan pagi jam 6");
  const proposal = mem.parts.find((p: any) => p.type === "memory_proposal");
  expect(proposal).toBeTruthy();
  expect((await call(`/api/me/memories/${proposal.memoryId}/confirm`, u.token, {})).status).toBe(200);
  const next = await say(u.token, crypto.randomUUID(), "ide olahraga ringan 10 menit");
  const msg = await prisma.conversationMessage.findFirstOrThrow({ where: { userId: u.id, role: "ASSISTANT", route: "ACTIVITY_PLAN" }, orderBy: { createdAt: "desc" } });
  expect(JSON.stringify(msg.basis ?? next)).toContain(proposal.memoryId);
  expect(next.parts.map((p: any) => p.text ?? "").join(" ")).toContain("Aku ingat");
});

test("Demo 4.0 kasus negatif: data kurang, permintaan medis, consent dicabut, data ganda, alat gagal", async () => {
  const u = await actor(PURPOSES);
  await call("/api/me/profile", u.token, { birthYear: 1990 }, "PATCH");
  await call("/api/me/health-profile", u.token, { diagnosisStatus: "not_diagnosed" }, "PUT");
  const thread = crypto.randomUUID();

  const sleep = await say(u.token, thread, "pola tidurku gimana");
  expect(sleep.route).toBe("SLEEP");
  expect(sleep.parts[0].text).toContain("belum cukup");

  const med = await say(u.token, thread, "berapa dosis metformin yang harus aku minum");
  expect(med.route).toBe("SAFETY");

  await call("/api/me/device-import/preferences", u.token, { sleep: true }, "PATCH");
  const s1 = { externalId: "w-1", startedAt: "2026-11-11T15:00:00.000Z", endedAt: "2026-11-11T22:00:00.000Z", dataOrigin: "com.watch.app" };
  const s2 = { externalId: "p-1", startedAt: "2026-11-11T15:30:00.000Z", endedAt: "2026-11-11T22:30:00.000Z", dataOrigin: "com.google.android.apps.fitness" };
  const one = await J(await call("/api/me/device-import", u.token, { source: "health_connect", sleep: [s1, s2] }));
  expect(one.sleep.created).toBe(2);
  const dup = await J(await call("/api/me/device-import", u.token, { source: "health_connect", sleep: [s1] }));
  expect(dup.sleep.duplicate).toBe(1);
  const status = await J(await call("/api/me/devices/status", u.token));
  const night = status.days.sleep.find((d: any) => d.value !== null);
  expect(night).toMatchObject({ status: "CONFLICT", value: 450 });

  const runRow = await prisma.agentRun.create({ data: { userId: u.id, status: "RUNNING", intent: "MEAL_DRAFT_ENRICHMENT", inputText: "x", idempotencyKey: crypto.randomUUID(), expiresAt: new Date(Date.now() + 60000) } });
  const saved = webSearchRef.current;
  webSearchRef.current = { configured: true, search: async () => { throw new Error("provider down"); } } as never;
  let code = "OK";
  try { await executeTool({ userId: u.id, runId: runRow.id, intent: "MEAL_DRAFT_ENRICHMENT", maxCalls: 8, callsUsed: 0 }, "search_web_nutrition", { query: "gado gado" }); } catch (e) { code = e instanceof ToolError ? e.code : "OTHER"; } finally { webSearchRef.current = saved; }
  expect(code).toBe("TOOL_FAILED");
  expect(await prisma.agentToolCall.count({ where: { runId: runRow.id, errorCode: "TOOL_FAILED" } })).toBe(1);

  await call("/api/me/consents/withdraw", u.token, { purposes: ["personalized_ai"] });
  const food = await say(u.token, thread, "cari info tempe");
  expect(food.parts.some((p: any) => p.type === "consent_required" && p.purpose === "personalized_ai")).toBe(true);
});
