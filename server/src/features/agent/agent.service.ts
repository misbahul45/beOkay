import { background } from "../../shared/runtime/background.ts";
import { activityWhy } from "./why.ts";
import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { AppError, conflict, notFound, unprocessable } from "../../shared/errors/app-error.ts";
import { consentService } from "../consent/consent.service.ts";
import { checkFood } from "../food-preferences/food-preferences.model.ts";
import { foodPreferencesService } from "../food-preferences/food-preferences.service.ts";
import { SAFETY_POLICY_VERSION, screenRequest } from "./agent.safety.ts";
import { buildRecommendation, queryTermsOf, runNutritionGraph, type RecommendationPayload } from "./agent.graph.ts";
import { buildActivityRecommendation, runActivityGraph, type ActivityConstraints } from "./activity.graph.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import type { ToolContext } from "./agent.tools.ts";
import { createMachine, FSM_VERSION, pathFor, RUN_STATUS_TO_FSM } from "./agent.fsm.ts";
import { personalization } from "./personalization.ts";
import { outbox } from "../../infrastructure/queue/outbox.ts";
import { env } from "../../config/env.ts";
import { outcomes } from "./outcomes.ts";
import { createTextWriter, type TextWriter } from "./llm-text.ts";
import type { Decision, Feedback, RunCreate } from "./agent.schema.ts";
import { classifyFollowUp, classifyIntent, extractQuery } from "./agent.intent.ts";
import { rateWindow } from "../../shared/http/rate-window.ts";

export const RUN_TTL_MS = 24 * 3_600_000;
export const STALE_RUN_MS = 120_000;
export const MAX_TOOL_CALLS = 8;
const RATE_WINDOW_MS = 10 * 60_000;
const RATE_MAX = 20;
const calls = rateWindow(RATE_WINDOW_MS, RATE_MAX);
export const MAX_TURNS = 20;
/** Dapat diganti pada tes unit; produksi memakai Mistral bila kunci tersedia. */
export const textWriterRef: { current: TextWriter } = { current: createTextWriter({ apiKey: env.MISTRAL_API_KEY, model: env.MISTRAL_AGENT_MODEL }) };

export { classifyFollowUp, classifyIntent, extractQuery };

async function consentOk(userId: string): Promise<boolean> {
  try {
    await consentService.requireConsent(userId, "health_data_processing");
    await consentService.requireConsent(userId, "personalized_ai");
    return true;
  } catch {
    return false;
  }
}
const requireAgentConsent = async (userId: string) => {
  await consentService.requireConsent(userId, "health_data_processing");
  await consentService.requireConsent(userId, "personalized_ai");
};

type RecRow = NonNullable<Awaited<ReturnType<typeof prisma.recommendation.findFirst>>>;
const recView = (r: RecRow) => {
  const p = r.payload as unknown as RecommendationPayload;
  return {
    id: r.id,
    runId: r.runId,
    type: r.recType,
    status: r.status,
    version: r.version,
    title: p.title,
    explanation: p.explanation,
    textSource: (p as unknown as { textSource?: string }).textSource ?? "TEMPLATE",
    candidate: p.candidate,
    activity: (p as unknown as { activity?: unknown }).activity ?? null,
    evidenceRefs: p.evidenceRefs,
    limitations: p.limitations,
    dataCoverage: p.dataCoverage,
    policyVersion: r.policyVersion,
    rankingReason: p.rankingReason,
    personalization: p.personalization,
    requiresConfirmation: true,
    expiresAt: r.expiresAt.toISOString(),
    decidedAt: r.decidedAt?.toISOString() ?? null,
  };
};

async function emit(runId: string, type: string, payload: Record<string, unknown> = {}) {
  for (let attempt = 0; ; attempt++) {
    const last = await prisma.agentRunEvent.findFirst({ where: { runId }, orderBy: { seq: "desc" }, select: { seq: true } });
    try {
      await prisma.agentRunEvent.create({ data: { runId, seq: (last?.seq ?? 0) + 1, type, payload: payload as Prisma.InputJsonObject } });
      return;
    } catch (e) {
      if (attempt < 4 && e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") continue;
      throw e;
    }
  }
}

const SKILL_OF_INTENT: Record<string, string> = { NUTRITION_ALTERNATIVES: "nutrition.coach", MEAL_DRAFT_ENRICHMENT: "nutrition.coach", ACTIVITY_PLAN: "activity.planner" };
const FSM_SETTLED = new Set(["WAITING_FOR_USER", "COMPLETED", "BLOCKED", "FAILED"]);

async function setStatus(runId: string, status: string, extra: Prisma.AgentRunUpdateInput = {}) {
  const row = await prisma.agentRun.update({ where: { id: runId }, data: { status, fsmState: RUN_STATUS_TO_FSM[status] ?? null, version: { increment: 1 }, ...extra } });
  if (!FSM_SETTLED.has(status)) return;
  if (await prisma.agentRunEvent.findFirst({ where: { runId, type: "FSM_PATH" }, select: { id: true } })) return;
  const usedTools = row.toolCallsUsed > 0;
  const path = pathFor(status, { usedTools, offered: status === "WAITING_FOR_USER" });
  const m = createMachine();
  for (const st of path.slice(1)) {
    if (st === "PLAN") m.beginIteration();
    m.to(st);
  }
  await prisma.agentRun.update({ where: { id: runId }, data: { fsmState: m.state, iterations: m.iterations, skillId: SKILL_OF_INTENT[row.intent] ?? null, skillVersion: SKILL_OF_INTENT[row.intent] ? "1" : null } });
  await emit(runId, "FSM_PATH", { version: FSM_VERSION, path, iterations: m.iterations, toolCalls: row.toolCallsUsed });
}

async function runView(userId: string, id: string) {
  const run = await prisma.agentRun.findFirst({ where: { id, userId } });
  if (!run) throw notFound("RUN_NOT_FOUND", "Run tidak ditemukan.");
  let current = run;
  const now = Date.now();
  // Pemulihan: run yang macet (proses mati di tengah jalan) ditandai gagal agar klien tidak menunggu selamanya.
  if (["CREATED", "VALIDATING", "RUNNING"].includes(current.status) && now - current.updatedAt.getTime() > STALE_RUN_MS) {
    await setStatus(id, "FAILED", { state: { ...(current.state as object), error: "STALE_RUN" } });
    current = await prisma.agentRun.findUniqueOrThrow({ where: { id } });
  }
  if (current.status === "WAITING_FOR_USER" && current.expiresAt.getTime() < now) {
    await prisma.$transaction([prisma.recommendation.updateMany({ where: { runId: id, status: "OFFERED" }, data: { status: "EXPIRED", version: { increment: 1 } } }), prisma.agentRun.update({ where: { id }, data: { status: "EXPIRED", version: { increment: 1 } } })]);
    current = await prisma.agentRun.findUniqueOrThrow({ where: { id } });
  }
  const allowed = await consentOk(userId);
  if (!allowed && current.status === "WAITING_FOR_USER") {
    await prisma.$transaction([prisma.recommendation.updateMany({ where: { runId: id, status: "OFFERED" }, data: { status: "INVALIDATED", version: { increment: 1 } } }), prisma.agentRun.update({ where: { id }, data: { status: "BLOCKED", safetyDecision: "CONSENT_WITHDRAWN", version: { increment: 1 } } })]);
    current = await prisma.agentRun.findUniqueOrThrow({ where: { id } });
  }
  const [events, recs] = await Promise.all([
    prisma.agentRunEvent.findMany({ where: { runId: id }, orderBy: { seq: "asc" }, take: 60 }),
    allowed ? prisma.recommendation.findMany({ where: { runId: id, userId }, orderBy: { createdAt: "asc" } }) : Promise.resolve([]),
  ]);
  const state = current.state as Record<string, unknown>;
  return {
    id: current.id,
    status: current.status,
    intent: current.intent,
    safetyDecision: current.safetyDecision,
    message: (state.message as string | undefined) ?? null,
    version: current.version,
    turn: current.turn,
    parentRunId: current.parentRunId,
    expiresAt: current.expiresAt.toISOString(),
    createdAt: current.createdAt.toISOString(),
    toolCallsUsed: current.toolCallsUsed,
    summary: { query: state.query ?? null, coverage: state.coverage ?? null, excludedByConstraints: state.excludedByConstraints ?? 0, rejectedByValidation: state.rejectedByValidation ?? 0, weakMatchesDropped: state.weakMatchesDropped ?? 0, profileVersion: state.profileVersion ?? null, preferencesConsidered: state.preferencesConsidered ?? 0 },
    events: events.map((e) => ({ seq: e.seq, type: e.type, payload: e.payload })),
    recommendations: recs.map(recView),
    consentRequired: !allowed,
  };
}

async function chainCandidateKeys(userId: string, fromRunId: string): Promise<Set<string>> {
  const keys = new Set<string>();
  let id: string | null = fromRunId;
  for (let i = 0; i < MAX_TURNS && id; i++) {
    const recs = await prisma.recommendation.findMany({ where: { runId: id, userId }, select: { payload: true } });
    for (const r of recs) keys.add((r.payload as unknown as RecommendationPayload).candidate.key);
    id = (await prisma.agentRun.findFirst({ where: { id, userId }, select: { parentRunId: true } }))?.parentRunId ?? null;
  }
  return keys;
}

async function explainWhy(userId: string, runId: string): Promise<string> {
  const recs = await prisma.recommendation.findMany({ where: { runId, userId }, orderBy: { createdAt: "asc" } });
  if (recs.length === 0) return "Belum ada saran sebelumnya untuk dijelaskan.";
  const activity = recs.filter((r) => r.recType === "ACTIVITY");
  if (activity.length > 0) {
    const now = Date.now();
    const sessions = await prisma.activitySession.findMany({ where: { userId, archivedAt: null, qualityStatus: { in: ["user_reported", "device_reported"] }, startedAt: { gte: new Date(now - 28 * 86_400_000) } }, select: { startedAt: true, durationMinutes: true } });
    const tz = (await preferencesService.get(userId)).timezone;
    const day = (d: Date) => new Intl.DateTimeFormat("en-CA", { timeZone: tz }).format(d);
    const active7 = new Set(sessions.filter((x) => x.startedAt.getTime() >= now - 7 * 86_400_000).map((x) => day(x.startedAt))).size;
    const mins = sessions.map((x) => x.durationMinutes);
    const facts = { activeDays7: active7, sessions28: sessions.length, longestMinutes: mins.length ? Math.max(...mins) : null, shortestMinutes: mins.length ? Math.min(...mins) : null };
    return activity
      .map((r) => {
        const p = r.payload as unknown as RecommendationPayload & { activity?: { durationMinutes: number } };
        return activityWhy(p.candidate.name, p.activity?.durationMinutes ?? 10, facts);
      })
      .join(" ");
  }
  return recs.map((r) => { const p = r.payload as unknown as RecommendationPayload; return `${p.candidate.name}: ${p.rankingReason} ${p.limitations[0] ?? ""}`.trim(); }).join(" ");
}

/** Teks LLM opsional. Hanya untuk pengguna dengan persetujuan ai_text_generation; selalu lewat gerbang dan jatuh ke templat bila gagal. */
async function polish<T extends { explanation: string; candidate: { name: string; provenance: string; per100g: Record<string, number | null> }; query: string; personalization: { matchedTerms: string[]; boostedTerms?: string[] } }>(userId: string, runId: string, kind: "NUTRITION" | "ACTIVITY", payloads: T[]): Promise<(T & { textSource: string })[]> {
  const base = payloads.map((p) => ({ ...p, textSource: "TEMPLATE" }));
  const writer = textWriterRef.current;
  if (!writer.configured || payloads.length === 0) return base;
  try {
    await consentService.requireConsent(userId, "ai_text_generation");
  } catch {
    return base;
  }
  const results = await Promise.all(payloads.map((p) => writer.write({ kind, name: p.candidate.name, template: p.explanation, facts: { sumber: p.candidate.provenance, per100g: Object.fromEntries(Object.entries(p.candidate.per100g).filter(([, v]) => v !== null)), pencarian: p.query, istilahDitolak: p.personalization.matchedTerms, istilahDisukai: p.personalization.boostedTerms ?? [] } })));
  await emit(runId, "LLM_TEXT", { model: env.MISTRAL_AGENT_MODEL, used: results.filter((r) => r.source === "LLM").length, total: results.length, fallbacks: results.filter((r) => r.fallbackReason).map((r) => r.fallbackReason), maxLatencyMs: Math.max(...results.map((r) => r.latencyMs)) });
  return base.map((p, i) => (results[i]!.source === "LLM" ? { ...p, explanation: results[i]!.text, textSource: "LLM" } : p));
}

export const agentService = {
  async createRun(userId: string, input: RunCreate, opts: { background?: boolean } = {}) {
    await requireAgentConsent(userId);
    const t = Date.now();
    if (calls.full(userId, t)) throw new AppError(429, "AGENT_RATE_LIMITED", "Terlalu banyak permintaan. Coba lagi beberapa menit lagi.");

    const existing = await prisma.agentRun.findUnique({ where: { userId_idempotencyKey: { userId, idempotencyKey: input.idempotencyKey } } });
    if (existing) {
      if (existing.inputText !== input.message) throw conflict("IDEMPOTENCY_CONFLICT", "Kunci idempotensi dipakai dengan pesan berbeda.");
      return runView(userId, existing.id);
    }
    let parent: Awaited<ReturnType<typeof prisma.agentRun.findFirst>> = null;
    if (input.previousRunId) {
      parent = await prisma.agentRun.findFirst({ where: { id: input.previousRunId, userId } }); // run milik pengguna lain tampil sebagai tidak ditemukan
      if (!parent) throw notFound("RUN_NOT_FOUND", "Percakapan sebelumnya tidak ditemukan.");
      if (parent.turn >= MAX_TURNS) throw unprocessable("CONVERSATION_TOO_LONG", "Percakapan sudah terlalu panjang. Mulai percakapan baru.");
    }
    calls.record(userId, t);

    let run;
    try {
      run = await prisma.agentRun.create({ data: { userId, status: "CREATED", intent: "PENDING", inputText: input.message, idempotencyKey: input.idempotencyKey, parentRunId: parent?.id ?? null, turn: (parent?.turn ?? 0) + 1, expiresAt: new Date(t + RUN_TTL_MS) } });
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") {
        const again = await prisma.agentRun.findUniqueOrThrow({ where: { userId_idempotencyKey: { userId, idempotencyKey: input.idempotencyKey } } });
        return runView(userId, again.id);
      }
      throw e;
    }
    await recordAudit(prisma, { userId, eventType: "agent_run_created", metadata: { runId: run.id } });
    await emit(run.id, "RUN_CREATED");
    if (opts.background) {
      // Mode streaming: balas segera dengan run yang baru dibuat; eksekusi berjalan di latar dan dapat diikuti lewat SSE.
      background(execute(userId, run, input, parent).catch(async (e) => {
        await setStatus(run.id, "FAILED", { state: { error: e instanceof Error ? e.message.slice(0, 80) : "UNKNOWN", message: "Terjadi kendala saat menyusun saran." } }).catch(() => {});
      }), "agent_run");
      return runView(userId, run.id);
    }
    return execute(userId, run, input, parent);
  },

  getRun: (userId: string, id: string) => runView(userId, id),

  /** Pemulihan setelah aplikasi dimulai ulang: run yang masih menunggu keputusan (terbaru 5), urut kronologis. Tanpa persetujuan: kosong. */
  async listPending(userId: string) {
    if (!(await consentOk(userId))) return { items: [], consentRequired: true };
    const rows = await prisma.agentRun.findMany({ where: { userId, status: "WAITING_FOR_USER", expiresAt: { gt: new Date() } }, orderBy: { createdAt: "desc" }, take: 5, select: { id: true } });
    const views = await Promise.all(rows.map((r) => runView(userId, r.id)));
    return { items: views.filter((v) => v.status === "WAITING_FOR_USER").reverse(), consentRequired: false };
  },

  async cancelRun(userId: string, id: string) {
    const run = await prisma.agentRun.findFirst({ where: { id, userId } });
    if (!run) throw notFound("RUN_NOT_FOUND", "Run tidak ditemukan.");
    if (run.status === "CANCELLED") return runView(userId, id);
    if (!["CREATED", "VALIDATING", "RUNNING", "WAITING_FOR_USER"].includes(run.status)) throw conflict("RUN_NOT_CANCELLABLE", "Run sudah selesai.", { status: run.status });
    await prisma.$transaction([prisma.recommendation.updateMany({ where: { runId: id, userId, status: "OFFERED" }, data: { status: "INVALIDATED", version: { increment: 1 } } }), prisma.agentRun.update({ where: { id }, data: { status: "CANCELLED", version: { increment: 1 } } })]);
    await emit(id, "RUN_CANCELLED");
    return runView(userId, id);
  },

  /** Keputusan pengguna. Idempoten lewat operationId; semua efek (rencana makan, personalisasi, status) dalam satu transaksi. */
  async decide(userId: string, recommendationId: string, input: Decision) {
    await requireAgentConsent(userId);
    const rec = await prisma.recommendation.findFirst({ where: { id: recommendationId, userId } });
    if (!rec) throw notFound("RECOMMENDATION_NOT_FOUND", "Saran tidak ditemukan.");

    const receipt = await prisma.recommendationDecision.findUnique({ where: { userId_operationId: { userId, operationId: input.operationId } } });
    if (receipt) {
      if (receipt.recommendationId !== recommendationId || receipt.decision !== input.decision) throw conflict("OPERATION_ID_REUSED", "operationId dipakai ulang untuk keputusan berbeda.");
      const fresh = await prisma.recommendation.findUniqueOrThrow({ where: { id: recommendationId } });
      return { replayed: true, recommendation: recView(fresh), plannedMealId: (await prisma.plannedMeal.findUnique({ where: { recommendationId } }))?.id ?? null, activityPlanId: (await prisma.activityPlan.findUnique({ where: { recommendationId } }))?.id ?? null };
    }

    if (rec.status !== "OFFERED") throw conflict("RECOMMENDATION_NOT_OFFERED", "Saran ini sudah tidak dapat diputuskan.", { status: rec.status });
    if (rec.expiresAt.getTime() < Date.now()) {
      await prisma.recommendation.updateMany({ where: { id: rec.id, status: "OFFERED" }, data: { status: "EXPIRED", version: { increment: 1 } } });
      throw conflict("RECOMMENDATION_EXPIRED", "Saran sudah kedaluwarsa.");
    }
    if (rec.version !== input.expectedVersion) throw conflict("VERSION_CONFLICT", "Saran berubah. Muat ulang.", { currentVersion: rec.version });
    const payload = rec.payload as unknown as RecommendationPayload;

    // Penerimaan diperiksa ulang terhadap kendala TERBARU (mis. alergi ditambahkan setelah saran ditawarkan).
    if (input.decision === "ACCEPT" && rec.recType === "NUTRITION") {
      const prefs = await foodPreferencesService.activeFor(userId);
      if (checkFood(payload.candidate.name, prefs).status === "EXCLUDED") {
        await prisma.recommendation.updateMany({ where: { id: rec.id, status: "OFFERED" }, data: { status: "INVALIDATED", version: { increment: 1 } } });
        throw conflict("RECOMMENDATION_NO_LONGER_ELIGIBLE", "Saran ini sekarang cocok dengan alergi atau pembatasanmu, jadi tidak dapat diterima.");
      }
    }

    try {
      return await prisma.$transaction(async (tx) => {
        const run = await tx.agentRun.findFirst({ where: { id: rec.runId, userId } });
        if (!run || run.status !== "WAITING_FOR_USER") throw conflict("RUN_NOT_WAITING", "Run tidak lagi menunggu keputusan.", { status: run?.status ?? null });
        const moved = await tx.recommendation.updateMany({ where: { id: rec.id, userId, status: "OFFERED", version: rec.version }, data: { status: input.decision === "ACCEPT" ? "ACCEPTED" : "REJECTED", version: { increment: 1 }, decidedAt: new Date() } });
        if (moved.count !== 1) throw conflict("VERSION_CONFLICT", "Saran berubah bersamaan. Muat ulang.");
        await tx.recommendationDecision.create({ data: { userId, recommendationId: rec.id, operationId: input.operationId, decision: input.decision, resultVersion: rec.version + 1 } });
        let plannedMealId: string | null = null;
        let activityPlanId: string | null = null;
        let profileVersion: number | null = null;
        if (input.decision === "ACCEPT" && rec.recType === "ACTIVITY") {
          const act = (payload as unknown as { activity: { type: string; durationMinutes: number } }).activity;
          const tz = (await preferencesService.get(userId)).timezone;
          const plan = await tx.activityPlan.create({ data: { userId, recommendationId: rec.id, activityType: act.type, durationMinutes: act.durationMinutes, plannedFor: new Date(localRecordTime(new Date(), tz).localDate + "T00:00:00Z"), status: "CONFIRMED" } });
          activityPlanId = plan.id;
        } else if (input.decision === "ACCEPT") {
          const planned = await tx.plannedMeal.create({ data: { userId, recommendationId: rec.id, name: payload.candidate.name, source: payload.candidate.source, sourceRef: ((payload.evidenceRefs[0] as { code?: string; foodId?: string } | undefined)?.code ?? (payload.evidenceRefs[0] as { foodId?: string } | undefined)?.foodId) ?? null, per100g: payload.candidate.per100g as Prisma.InputJsonObject, status: "PLANNED" } });
          plannedMealId = planned.id;
        } else if (rec.recType === "NUTRITION") {
          profileVersion = (await personalization.applyRejection(tx, userId, rec.id, payload.candidate.name, queryTermsOf(payload.query)))?.version ?? null;
        }
        await recordAudit(tx, { userId, eventType: "agent_recommendation_decided", metadata: { recommendationId: rec.id, decision: input.decision } });
        await outbox.enqueue(tx, { userId, type: "recommendation.decided", payload: { recommendationId: rec.id, decision: input.decision, recType: rec.recType }, dedupeKey: `decided:${userId}:${input.operationId}` });
        const open = await tx.recommendation.count({ where: { runId: rec.runId, status: "OFFERED" } });
        const m = createMachine({}, Date.now, "AWAIT_CONFIRMATION");
        if (input.decision === "ACCEPT") {
          m.authorize({ operationId: input.operationId, decision: "ACCEPT" });
          m.to("OBSERVE_OUTCOME", rec.recType === "ACTIVITY" ? "activity_plan" : "planned_meal");
        }
        if (open === 0) m.to("COMPLETED");
        const seq = (await tx.agentRunEvent.aggregate({ where: { runId: rec.runId }, _max: { seq: true } }))._max.seq ?? 0;
        await tx.agentRunEvent.create({ data: { runId: rec.runId, seq: seq + 1, type: "FSM_DECISION", payload: { version: FSM_VERSION, recommendationId: rec.id, decision: input.decision, receipt: input.operationId, path: m.history.map((h) => h.to) } } });
        await tx.agentRun.update({ where: { id: rec.runId }, data: { ...(open === 0 ? { status: "COMPLETED" } : {}), fsmState: m.state, version: { increment: 1 } } });
        const fresh = await tx.recommendation.findUniqueOrThrow({ where: { id: rec.id } });
        return { replayed: false, recommendation: recView(fresh), plannedMealId, activityPlanId, personalizationVersion: profileVersion };
      });
    } catch (e) {
      // Dua permintaan dengan operationId sama bersamaan: yang kedua mendapat 409 dan mengulang, lalu menerima balasan tersimpan.
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") throw conflict("DECISION_IN_PROGRESS", "Keputusan sedang diproses. Ulangi permintaan yang sama.");
      throw e;
    }
  },

  /** Umpan balik untuk rencana yang DITERIMA. Makanan: konsumsi/tidak. Aktivitas: selesai/dilewati (+ sesi opsional). Tidak membuat catatan makan atau sesi. */
  async feedback(userId: string, recommendationId: string, input: Feedback) {
    await requireAgentConsent(userId);
    const rec = await prisma.recommendation.findFirst({ where: { id: recommendationId, userId } });
    if (!rec) throw notFound("RECOMMENDATION_NOT_FOUND", "Saran tidak ditemukan.");
    const nutritionKinds = ["CONSUMED", "NOT_CONSUMED"];
    if ((rec.recType === "NUTRITION") !== nutritionKinds.includes(input.kind)) throw unprocessable("FEEDBACK_KIND_MISMATCH", "Jenis umpan balik tidak sesuai dengan jenis saran.");
    const prior = await prisma.recommendationFeedback.findUnique({ where: { userId_operationId: { userId, operationId: input.operationId } } });
    if (prior) {
      if (prior.recommendationId !== recommendationId || prior.kind !== input.kind) throw conflict("OPERATION_ID_REUSED", "operationId dipakai ulang untuk umpan balik berbeda.");
      return { replayed: true, plannedMeal: await plannedView(recommendationId), activityPlan: await activityPlanView(recommendationId) };
    }
    if (rec.status !== "ACCEPTED") throw conflict("RECOMMENDATION_NOT_ACCEPTED", "Umpan balik hanya untuk saran yang kamu terima.", { status: rec.status });
    try {
      await prisma.$transaction(async (tx) => {
        if (rec.recType === "NUTRITION") {
          const plan = await tx.plannedMeal.findUnique({ where: { recommendationId } });
          if (!plan) throw notFound("PLANNED_MEAL_NOT_FOUND", "Rencana makan tidak ditemukan.");
          if (plan.status !== "PLANNED") throw conflict("FEEDBACK_ALREADY_RECORDED", "Umpan balik untuk rencana ini sudah dicatat.", { status: plan.status });
          await tx.recommendationFeedback.create({ data: { userId, recommendationId, operationId: input.operationId, kind: input.kind } });
          const moved = await tx.plannedMeal.updateMany({ where: { id: plan.id, userId, status: "PLANNED", version: plan.version }, data: { status: input.kind === "CONSUMED" ? "CONSUMED" : "SKIPPED", version: { increment: 1 } } });
          if (moved.count !== 1) throw conflict("FEEDBACK_ALREADY_RECORDED", "Umpan balik untuk rencana ini sudah dicatat.");
        } else {
          const plan = await tx.activityPlan.findUnique({ where: { recommendationId } });
          if (!plan) throw notFound("ACTIVITY_PLAN_NOT_FOUND", "Rencana aktivitas tidak ditemukan.");
          if (plan.status !== "CONFIRMED") throw conflict("FEEDBACK_ALREADY_RECORDED", "Umpan balik untuk rencana ini sudah dicatat.", { status: plan.status });
          let linked: string | null = null;
          if (input.kind === "COMPLETED" && input.activitySessionId) {
            const session = await tx.activitySession.findFirst({ where: { id: input.activitySessionId, userId, archivedAt: null }, select: { id: true } });
            if (!session) throw unprocessable("SESSION_NOT_FOUND", "Sesi aktivitas tidak ditemukan.");
            linked = session.id;
          }
          await tx.recommendationFeedback.create({ data: { userId, recommendationId, operationId: input.operationId, kind: input.kind } });
          const moved = await tx.activityPlan.updateMany({ where: { id: plan.id, userId, status: "CONFIRMED", version: plan.version }, data: { status: input.kind === "COMPLETED" ? "COMPLETED" : "SKIPPED", linkedSessionId: linked, version: { increment: 1 } } });
          if (moved.count !== 1) throw conflict("FEEDBACK_ALREADY_RECORDED", "Umpan balik untuk rencana ini sudah dicatat.");
        }
        await recordAudit(tx, { userId, eventType: "agent_feedback_recorded", metadata: { recommendationId, kind: input.kind } });
        await outbox.enqueue(tx, { userId, type: "recommendation.feedback", payload: { recommendationId, kind: input.kind }, dedupeKey: `feedback:${userId}:${input.operationId}` });
      });
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") throw conflict("DECISION_IN_PROGRESS", "Permintaan sedang diproses. Ulangi.");
      throw e;
    }
    return { replayed: false, plannedMeal: await plannedView(recommendationId), activityPlan: await activityPlanView(recommendationId), note: rec.recType === "NUTRITION" ? "Ini tidak membuat catatan makan. Catat konsumsi sebenarnya di Catatan jika kamu mau." : "Ini tidak membuat sesi aktivitas. Catat sesi sebenarnya di Aktivitas jika kamu mau." };
  },

  async listActivityPlans(userId: string) {
    await consentService.requireConsent(userId, "health_data_processing");
    await outcomes.reconcile(userId);
    const rows = await prisma.activityPlan.findMany({ where: { userId }, orderBy: [{ createdAt: "desc" }, { id: "desc" }], take: 50 });
    const out = await outcomeMap(userId, rows.map((r) => r.recommendationId));
    return { items: rows.map((r) => ({ ...activityPlanRow(r), measuredOutcome: out.get(r.recommendationId) ?? null })) };
  },

  async listPlannedMeals(userId: string) {
    await consentService.requireConsent(userId, "health_data_processing");
    await outcomes.reconcile(userId);
    const rows = await prisma.plannedMeal.findMany({ where: { userId }, orderBy: [{ createdAt: "desc" }, { id: "desc" }], take: 50 });
    const out = await outcomeMap(userId, rows.map((r) => r.recommendationId));
    return { items: rows.map((r) => ({ ...plannedRow(r), measuredOutcome: out.get(r.recommendationId) ?? null })) };
  },
};

type RunRow = NonNullable<Awaited<ReturnType<typeof prisma.agentRun.findFirst>>>;
async function execute(userId: string, run: RunRow, input: RunCreate, parent: RunRow | null) {

    // Gerbang keselamatan permintaan: sebelum alat apa pun dijalankan.
    await setStatus(run.id, "VALIDATING");
    const screen = screenRequest(input.message);
    await emit(run.id, "SAFETY_SCREEN", { decision: screen.decision, policy: SAFETY_POLICY_VERSION, ...(screen.decision !== "ALLOWED" ? { code: screen.code } : {}) });
    if (screen.decision !== "ALLOWED") {
      await setStatus(run.id, "BLOCKED", { intent: "BLOCKED_BY_POLICY", safetyDecision: screen.code, state: { message: screen.message } });
      return runView(userId, run.id);
    }

    const follow = parent ? classifyFollowUp(input.message) : null;
    if (parent) await emit(run.id, "FOLLOW_UP", { parentRunId: parent.id, turn: run.turn, kind: follow ?? "NEW_REQUEST" });
    if (follow === "WHY") {
      await setStatus(run.id, "COMPLETED", { intent: "FOLLOW_UP_WHY", state: { message: await explainWhy(userId, parent!.id) } });
      return runView(userId, run.id);
    }
    let exclude: ReadonlySet<string> = new Set();
    let parentQuery: string | null = null;
    if (follow === "MORE") {
      if (!["NUTRITION_ALTERNATIVES", "ACTIVITY_PLAN"].includes(parent!.intent)) {
        await setStatus(run.id, "COMPLETED", { intent: "FOLLOW_UP_MORE", state: { message: "Belum ada saran sebelumnya yang bisa dilanjutkan. Tulis permintaan baru, misalnya \"alternatif pengganti nasi goreng\"." } });
        return runView(userId, run.id);
      }
      exclude = await chainCandidateKeys(userId, parent!.id);
      parentQuery = ((parent!.state as Record<string, unknown>).query as string | undefined) ?? null;
    }
    const intent = follow === "MORE" ? (parent!.intent as "NUTRITION_ALTERNATIVES" | "ACTIVITY_PLAN") : (input.intent ?? classifyIntent(input.message, input.query));
    if (intent === "UNSUPPORTED") {
      await setStatus(run.id, "COMPLETED", { intent, state: { message: "Saat ini saya baru bisa membantu mencari alternatif makanan. Coba tulis, misalnya: \"alternatif pengganti nasi goreng\"." } });
      return runView(userId, run.id);
    }
    if (intent === "ACTIVITY_PLAN") return runActivity(userId, run.id, input.message, exclude, input.activity ?? {});
    const query = follow === "MORE" ? parentQuery : (input.query ?? extractQuery(input.message));
    if (!query) {
      await setStatus(run.id, "COMPLETED", { intent, state: { outcome: "NEEDS_CLARIFICATION", message: "Makanan apa yang ingin dicari alternatifnya? Tulis nama makanannya." } });
      return runView(userId, run.id);
    }

    await setStatus(run.id, "RUNNING", { intent });
    const ctx: ToolContext = { userId, runId: run.id, intent, maxCalls: MAX_TOOL_CALLS, callsUsed: 0 };
    try {
      const outcome = await runNutritionGraph(ctx, query, exclude);
      for (const e of outcome.events) await emit(run.id, e.type, e.payload);
      const strict = outcome.preferencesConsidered > 0 && (await foodPreferencesService.activeFor(userId)).some((p) => p.severity === "strict");
      const state = { query, coverage: outcome.coverage, excludedByConstraints: outcome.excludedByConstraints, rejectedByValidation: outcome.rejectedByValidation, weakMatchesDropped: outcome.weakMatchesDropped, profileVersion: outcome.profileVersion, preferencesConsidered: outcome.preferencesConsidered };
      if (outcome.offered.length === 0) {
        await setStatus(run.id, "COMPLETED", { toolCallsUsed: ctx.callsUsed, state: { ...state, outcome: "INSUFFICIENT_DATA", message: follow === "MORE" ? "Tidak ada pilihan lain yang cocok dan bersumber untuk pencarian itu." : outcome.excludedByConstraints > 0 ? "Semua kandidat yang ditemukan cocok dengan alergi atau pembatasanmu, jadi tidak ada yang ditawarkan." : outcome.weakMatchesDropped > 0 ? `Belum menemukan makanan yang cocok dengan "${query}". Coba nama yang lebih spesifik.` : "Tidak ada kandidat bergizi bersumber yang ditemukan untuk pencarian itu. Coba kata kunci lain." } });
        return runView(userId, run.id);
      }
      const expiresAt = new Date(Date.now() + RUN_TTL_MS);
      const payloads = await polish(userId, run.id, "NUTRITION", outcome.offered.map((c) => buildRecommendation(c, outcome, query, strict)));
      await prisma.$transaction([
        ...payloads.map((payload) => prisma.recommendation.create({ data: { userId, runId: run.id, recType: "NUTRITION", status: "OFFERED", payload: payload as unknown as Prisma.InputJsonObject, policyVersion: SAFETY_POLICY_VERSION, expiresAt } })),
        prisma.agentRun.update({ where: { id: run.id }, data: { status: "WAITING_FOR_USER", version: { increment: 1 }, toolCallsUsed: ctx.callsUsed, safetyDecision: "NEEDS_USER_CONFIRMATION", state: { ...state, message: "Pilih satu atau tolak. Tidak ada yang tersimpan sampai kamu menyetujuinya." } } }),
      ]);
      await emit(run.id, "RECOMMENDATIONS_OFFERED", { count: outcome.offered.length });
    } catch (e) {
      await setStatus(run.id, "FAILED", { toolCallsUsed: ctx.callsUsed, state: { error: e instanceof Error ? e.message.slice(0, 80) : "UNKNOWN", message: "Terjadi kendala saat menyusun saran. Pencatatan kesehatanmu tidak terpengaruh." } });
      await emit(run.id, "RUN_FAILED", { code: e instanceof Error ? e.name : "UNKNOWN" });
    }
    return runView(userId, run.id);
}

async function runActivity(userId: string, runId: string, message: string, exclude: ReadonlySet<string> = new Set(), constraints: ActivityConstraints = {}) {
  await setStatus(runId, "RUNNING", { intent: "ACTIVITY_PLAN" });
  const ctx: ToolContext = { userId, runId, intent: "ACTIVITY_PLAN", maxCalls: MAX_TOOL_CALLS, callsUsed: 0 };
  try {
    const outcome = await runActivityGraph(ctx, exclude, constraints);
    for (const e of outcome.events) await emit(runId, e.type, e.payload);
    const query = message.slice(0, 80);
    if (outcome.offered.length === 0) {
      await setStatus(runId, "COMPLETED", { toolCallsUsed: ctx.callsUsed, state: { query, message: "Tidak ada pilihan aktivitas lain yang bisa disarankan dari riwayatmu." } });
      return runView(userId, runId);
    }
    const expiresAt = new Date(Date.now() + RUN_TTL_MS);
    const payloads = await polish(userId, runId, "ACTIVITY", outcome.offered.map((c) => buildActivityRecommendation(c, outcome, query)));
    await prisma.$transaction([
      ...payloads.map((payload) => prisma.recommendation.create({ data: { userId, runId, recType: "ACTIVITY", status: "OFFERED", payload: payload as unknown as Prisma.InputJsonObject, policyVersion: SAFETY_POLICY_VERSION, expiresAt } })),
      prisma.agentRun.update({ where: { id: runId }, data: { status: "WAITING_FOR_USER", version: { increment: 1 }, toolCallsUsed: ctx.callsUsed, safetyDecision: "NEEDS_USER_CONFIRMATION", state: { query, coverage: { activity: outcome.coverage }, profileVersion: outcome.profileVersion, preferencesConsidered: 0, excludedByConstraints: 0, rejectedByValidation: 0, message: "Pilih satu atau tolak. Tidak ada yang tersimpan sampai kamu menyetujuinya." } } }),
    ]);
    await emit(runId, "RECOMMENDATIONS_OFFERED", { count: outcome.offered.length });
  } catch (e) {
    await setStatus(runId, "FAILED", { toolCallsUsed: ctx.callsUsed, state: { error: e instanceof Error ? e.message.slice(0, 80) : "UNKNOWN", message: "Terjadi kendala saat menyusun saran. Pencatatanmu tidak terpengaruh." } });
    await emit(runId, "RUN_FAILED", { code: e instanceof Error ? e.name : "UNKNOWN" });
  }
  return runView(userId, runId);
}

/** Hasil TERUKUR dari catatan nyata (berbeda dari umpan balik yang dilaporkan sendiri). */
async function outcomeMap(userId: string, ids: string[]) {
  const rows = await prisma.recommendationOutcome.findMany({ where: { userId, recommendationId: { in: ids } } });
  return new Map(rows.map((o) => [o.recommendationId, { kind: o.kind, observedAt: o.observedAt.toISOString() }]));
}

type Planned = NonNullable<Awaited<ReturnType<typeof prisma.plannedMeal.findFirst>>>;
const plannedRow = (p: Planned) => ({ id: p.id, recommendationId: p.recommendationId, name: p.name, source: p.source, sourceRef: p.sourceRef, per100g: p.per100g, status: p.status, version: p.version, createdAt: p.createdAt.toISOString() });
async function plannedView(recommendationId: string) {
  const p = await prisma.plannedMeal.findUnique({ where: { recommendationId } });
  return p ? plannedRow(p) : null;
}

type PlanRow = NonNullable<Awaited<ReturnType<typeof prisma.activityPlan.findFirst>>>;
const activityPlanRow = (p: PlanRow) => ({ id: p.id, recommendationId: p.recommendationId, activityType: p.activityType, durationMinutes: p.durationMinutes, plannedFor: p.plannedFor.toISOString().slice(0, 10), status: p.status, linkedSessionId: p.linkedSessionId, version: p.version });
async function activityPlanView(recommendationId: string) {
  const p = await prisma.activityPlan.findUnique({ where: { recommendationId } });
  return p ? activityPlanRow(p) : null;
}
