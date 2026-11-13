import { prisma } from "../../../infrastructure/database/prisma.ts";
import type { Prisma } from "../../../generated/prisma/client.ts";
import { BARRIER_LABEL, type Barrier } from "../../coaching/coaching.strategies.ts";
import type { Journey } from "../../cohort/cohort.policy.ts";
import type { Certainty } from "../../knowledge/knowledge.model.ts";
import type { RetrievalResult } from "../../knowledge/knowledge.service.ts";
import { explanationIsSafe } from "../agent.safety.ts";
import { INJECTION_PATTERN } from "../../conversation/intent-classifier.ts";
import { createMachine, FSM_VERSION, FsmError, type Machine } from "../agent.fsm.ts";
import { executeTool, ToolError } from "../agent.tools.ts";
import type { Skill } from "./registry.ts";
import { featureFlags } from "../../feature-flags/feature-flags.service.ts";
import { llmPlannerRef, LLM_PLANNER_VERSION } from "./llm-planner.ts";

export type Block =
  | { type: "text"; text: string }
  | { type: "notice"; tone: "info" | "warning"; text: string }
  | { type: "education"; items: { key: string; title: string; readMinutes: number; reviewStatus: "DRAFT" | "REVIEWED" }[] }
  | { type: "evidence"; certainty: Certainty; items: { title: string; source: string; reviewStatus: string; lane: string }[] }
  | { type: "strategy"; barrier: Barrier; key: string; title: string; detail: string; reviewStatus: string }
  | { type: "consent_required"; purpose: string };

export type SkillResult = {
  runId: string;
  skillId: string;
  status: "COMPLETED" | "BLOCKED" | "FAILED";
  blocks: Block[];
  certainty: Certainty;
  memoryIds: string[];
  sources: { kind: string; label: string }[];
  fsm: { state: string; iterations: number; toolCalls: number; path: string[] };
};

type Ctx = { userId: string; runId: string; skill: Skill; machine: Machine; journey: Journey; text: string };

async function tool<T>(c: Ctx, name: string, args: unknown): Promise<T | null> {
  if (c.machine.remainingTools() <= 0) return null;
  c.machine.useTool();
  try {
    return await executeTool<T>({ userId: c.userId, runId: c.runId, intent: c.skill.intent, maxCalls: c.skill.maxToolCalls, callsUsed: c.machine.toolCalls - 1, allowedTools: c.skill.allowedTools, iteration: c.machine.iterations, skillId: c.skill.id }, name, args);
  } catch (e) {
    if (e instanceof ToolError) return null;
    throw e;
  }
}

type Evidence = { facts?: FactsResult | null; quality?: QualityResult | null; knowledge?: RetrievalResult | null; memory?: MemoryResult | null };
type FactsResult = { windowDays: number; deviceDataIncluded: boolean; certainty: Certainty; days: { date: string; activeMinutes: number; sessions: number; steps: number | null; sleepMinutes: number | null; meals: number }[] };
type QualityResult = { signals: { signal: string; coverage: number; observedDays: number; reliable: boolean; statusCounts: Record<string, number> }[] };
type MemoryResult = { ids: string[]; items: { id: string; kind: string; content: string }[] };

type Planner = (c: Ctx, ev: Evidence, iteration: number) => { name: string; args: unknown; slot: keyof Evidence } | null;
type Sufficient = (ev: Evidence) => boolean;
type Composer = (c: Ctx, ev: Evidence) => { blocks: Block[]; certainty: Certainty; sources: { kind: string; label: string }[] };

export function classifyBarrier(text: string): Barrier {
  const t = text.toLowerCase();
  if (/(lupa|kelupaan|terlewat|kelewat)/.test(t)) return "FORGOT";
  if (/(sibuk|nggak sempat|tidak sempat|gak sempat|ga sempat|waktu|kerja terus|lembur)/.test(t)) return "TIME";
  if (/(capek|capai|lelah|letih|ngantuk|lemas|tenaga)/.test(t)) return "ENERGY";
  if (/(malas|males|bosan|nggak semangat|tidak semangat|susah konsisten|motivasi)/.test(t)) return "MOTIVATION";
  return "OTHER";
}

const hm = (m: number) => `${Math.floor(m / 60)} jam ${m % 60} menit`;

const SKILL_IMPL: Record<string, { plan: Planner; sufficient: Sufficient; compose: Composer }> = {
  "sleep.recovery": {
    plan: (_c, ev) => {
      if (ev.facts === undefined) return { name: "get_daily_facts", args: { days: 14 }, slot: "facts" };
      if (ev.quality === undefined) return { name: "get_device_quality", args: {}, slot: "quality" };
      if (ev.knowledge === undefined) return { name: "search_knowledge", args: { query: "tidur pulih kebiasaan tidur", lane: "A_PUBLIC_HEALTH", limit: 1 }, slot: "knowledge" };
      return null;
    },
    sufficient: (ev) => ev.facts !== undefined && ev.quality !== undefined && ev.knowledge !== undefined,
    compose: (_c, ev) => {
      const blocks: Block[] = [];
      const nights = (ev.facts?.days ?? []).filter((d) => d.sleepMinutes !== null);
      const sources = [{ kind: "STATISTICS", label: "Fakta harian 14 hari dari catatan dan perangkat" }];
      let certainty: Certainty = "insufficient";
      if (!ev.facts?.deviceDataIncluded) {
        blocks.push({ type: "text", text: "Data tidur dari perangkat belum dipakai untuk saran karena persetujuannya belum diberikan. Kamu bisa menyalakannya di Privasi & data." });
        blocks.push({ type: "consent_required", purpose: "device_data_coaching" });
      } else if (nights.length < 3) {
        blocks.push({ type: "text", text: `Dalam 14 hari terakhir baru ${nights.length} malam yang punya data tidur. Itu belum cukup untuk melihat pola, dan malam tanpa data tidak dianggap kurang tidur.` });
      } else {
        const avg = Math.round(nights.reduce((s, d) => s + (d.sleepMinutes ?? 0), 0) / nights.length);
        const sleepQ = ev.quality?.signals.find((s) => s.signal === "sleep");
        certainty = sleepQ?.reliable ? "estimated" : "insufficient";
        blocks.push({ type: "text", text: `Dari ${nights.length} malam yang tercatat dalam 14 hari, rata-rata tidurmu sekitar ${hm(avg)}. Angka ini perkiraan perangkat, bukan penilaian kesehatan.` });
        if ((sleepQ?.statusCounts.CONFLICT ?? 0) > 0) blocks.push({ type: "notice", tone: "info", text: "Ada malam yang direkam dua perangkat sekaligus. Waktu yang tumpang tindih hanya dihitung sekali." });
      }
      const k = ev.knowledge;
      if (k?.decision.status === "ANSWER" && k.items[0]) {
        const it = k.items[0];
        blocks.push({ type: "text", text: it.text });
        blocks.push({ type: "evidence", certainty: k.certainty, items: k.items.map((i) => ({ title: i.title, source: i.sourceName, reviewStatus: i.reviewStatus, lane: i.lane })) });
        sources.push({ kind: "KNOWLEDGE", label: `Bacaan: ${it.title}` });
      }
      blocks.push({ type: "notice", tone: "info", text: "Bila tidur terus terganggu, mendengkur keras, atau kantuk berat di siang hari, bicarakan dengan tenaga kesehatan." });
      return { blocks, certainty, sources };
    },
  },
  "behavior.barrier_solver": {
    plan: (c, ev, iteration) => {
      if (ev.memory === undefined && c.skill.allowedTools.includes("get_memory_context")) return { name: "get_memory_context", args: { skillId: c.skill.id, budget: 3 }, slot: "memory" };
      const barrier = classifyBarrier(c.text);
      if (ev.knowledge === undefined) return { name: "search_knowledge", args: { query: `${BARRIER_LABEL[barrier]} ${c.text}`.slice(0, 160), lane: "C_BEHAVIOR_STRATEGY", limit: 1 }, slot: "knowledge" };
      if (ev.knowledge?.decision.status === "ABSTAIN" && iteration < c.machine.budget.maxIterations) return { name: "search_knowledge", args: { query: `hambatan ${BARRIER_LABEL[barrier]} ${barrier.toLowerCase()}`, lane: "C_BEHAVIOR_STRATEGY", limit: 1 }, slot: "knowledge" };
      return null;
    },
    sufficient: (ev) => ev.knowledge?.decision.status === "ANSWER",
    compose: (c, ev) => {
      const barrier = classifyBarrier(c.text);
      const k = ev.knowledge;
      const blocks: Block[] = [];
      const sources: { kind: string; label: string }[] = [{ kind: "MESSAGE", label: "Hambatan yang kamu ceritakan" }];
      if (k?.decision.status === "ANSWER" && k.items[0]) {
        const it = k.items[0];
        const key = it.slug.replace(/^strategy:/, "").replace(/@v\d+$/, "");
        blocks.push({ type: "strategy", barrier, key, title: it.title, detail: it.text, reviewStatus: it.reviewStatus });
        blocks.push({ type: "text", text: `Satu cara yang bisa dicoba: ${it.title.toLowerCase()}. ${it.text.split(" Hambatan:")[0]}` });
        sources.push({ kind: "KNOWLEDGE", label: `Katalog strategi: ${it.title}` });
        return { blocks, certainty: k.certainty, sources };
      }
      return { blocks, certainty: "unknown", sources };
    },
  },
  "prevention.education": {
    plan: (c, ev, iteration) => {
      if (ev.knowledge === undefined) return { name: "search_knowledge", args: { query: c.text.slice(0, 160), lane: "A_PUBLIC_HEALTH", limit: 2 }, slot: "knowledge" };
      if (ev.knowledge?.decision.status === "ABSTAIN" && iteration < 2) return { name: "search_knowledge", args: { query: "pencegahan pemeriksaan rutin kebiasaan", lane: "A_PUBLIC_HEALTH", limit: 2 }, slot: "knowledge" };
      return null;
    },
    sufficient: (ev) => ev.knowledge?.decision.status === "ANSWER",
    compose: (_c, ev) => {
      const k = ev.knowledge;
      if (!k || k.decision.status !== "ANSWER" || !k.items.length) {
        return { blocks: [{ type: "text", text: "Aku belum punya bacaan yang cukup untuk pertanyaan itu, jadi aku tidak menjawabnya. Tanyakan ke tenaga kesehatanmu; mereka yang bisa menilai keadaanmu." }], certainty: "unknown", sources: [] };
      }
      const top = k.items[0]!;
      const blocks: Block[] = [
        { type: "text", text: `Dari bacaan “${top.title}”: ${top.text}` },
        { type: "evidence", certainty: k.certainty, items: k.items.map((i) => ({ title: i.title, source: i.sourceName, reviewStatus: i.reviewStatus, lane: i.lane })) },
      ];
      if (k.items.some((i) => i.reviewStatus !== "REVIEWED")) blocks.push({ type: "notice", tone: "warning", text: "Draf: bacaan ini belum ditinjau klinisi. Bacaan umum, bukan pengganti saran tenaga kesehatanmu." });
      return { blocks, certainty: k.certainty, sources: k.items.map((i) => ({ kind: "KNOWLEDGE", label: `Bacaan: ${i.title}` })) };
    },
  },
};

export function sanitize<T>(result: T, m?: Machine): T {
  const r = result as unknown as RetrievalResult | null;
  if (!r || typeof r !== "object" || !Array.isArray((r as RetrievalResult).items) || !("decision" in r)) return result;
  const clean = r.items.filter((i) => !INJECTION_PATTERN.test(i.text) && !INJECTION_PATTERN.test(i.title) && explanationIsSafe(i.text));
  if (clean.length === r.items.length) return result;
  m?.annotate(`tool_output_filtered:${r.items.length - clean.length}`);
  const decision = clean.length ? r.decision : { status: "ABSTAIN" as const, reason: "NO_CANDIDATES" as const };
  return { ...r, items: clean, decision, certainty: clean.length ? r.certainty : "unknown" } as unknown as T;
}

export const RUNNABLE_SKILLS = new Set(Object.keys(SKILL_IMPL));

export type ShadowPlan = { iteration: number; deterministic: string | null; proposed: string | null; agree: boolean; status: string; detail?: string; latencyMs: number };

async function shadowPropose(c: Ctx, ev: Evidence, iteration: number, deterministic: string | null): Promise<ShadowPlan> {
  const p = await llmPlannerRef.current.propose({ skillId: c.skill.id, intent: c.skill.intent, text: c.text, allowedTools: c.skill.allowedTools, evidence: Object.entries(ev).filter(([, v]) => v !== undefined).map(([k]) => k), iteration });
  return { iteration, deterministic, proposed: p.tool, agree: p.status === "OK" && p.tool === deterministic, status: p.status, ...(p.detail ? { detail: p.detail } : {}), latencyMs: p.latencyMs };
}

async function persistEvents(runId: string, m: Machine, extra: Record<string, unknown>, shadow: ShadowPlan[] = []) {
  const rows: Prisma.AgentRunEventCreateManyInput[] = m.history.map((h, i) => ({ runId, seq: i + 1, type: "FSM", payload: { from: h.from, to: h.to, at: h.at, ...(h.note ? { note: h.note } : {}) } }));
  rows.push({ runId, seq: rows.length + 1, type: "FSM_PATH", payload: { version: FSM_VERSION, path: ["RECEIVED", ...m.history.map((h) => h.to)], iterations: m.iterations, toolCalls: m.toolCalls, ...extra } as Prisma.InputJsonObject });
  for (const sp of shadow) rows.push({ runId, seq: rows.length + 1, type: "LLM_PLAN_SHADOW", payload: { version: LLM_PLANNER_VERSION, executed: false, ...sp } as Prisma.InputJsonObject });
  await prisma.agentRunEvent.createMany({ data: rows });
}

export async function runSkill(input: { userId: string; skill: Skill; text: string; idempotencyKey: string; journey: Journey; now?: Date }): Promise<SkillResult> {
  const { userId, skill } = input;
  const impl = SKILL_IMPL[skill.id];
  if (!impl) throw new Error(`SKILL_NOT_RUNNABLE:${skill.id}`);
  const existing = await prisma.agentRun.findUnique({ where: { userId_idempotencyKey: { userId, idempotencyKey: input.idempotencyKey } } });
  if (existing) return (existing.state as unknown as { result: SkillResult }).result;
  const now = input.now ?? new Date();
  const run = await prisma.agentRun.create({ data: { userId, status: "RUNNING", intent: skill.intent, inputText: input.text.slice(0, 2000), idempotencyKey: input.idempotencyKey, expiresAt: new Date(now.getTime() + 30 * 60_000), skillId: skill.id, skillVersion: skill.version, journey: input.journey, fsmState: "RECEIVED" } });
  const m = createMachine({ maxIterations: skill.maxIterations, maxToolCalls: skill.maxToolCalls, deadlineMs: skill.timeoutMs });
  const c: Ctx = { userId, runId: run.id, skill, machine: m, journey: input.journey, text: input.text };
  const ev: Evidence = {};
  let status: SkillResult["status"] = "COMPLETED";
  let composed: ReturnType<Composer> = { blocks: [], certainty: "unknown", sources: [] };
  const shadowOn = llmPlannerRef.current.configured && (await featureFlags.isEnabled("react_llm_planner"));
  const shadow: ShadowPlan[] = [];
  try {
    m.to("SAFETY_SCREEN");
    m.to("ROUTE");
    m.to("SELECT_SKILL", skill.id);
    while (m.beginIteration()) {
      m.to("PLAN", `iteration:${m.iterations}`);
      let step = impl.plan(c, ev, m.iterations);
      if (shadowOn) shadow.push(await shadowPropose(c, ev, m.iterations, step?.name ?? null));
      if (!step) {
        m.to("DRAFT_RESPONSE");
        break;
      }
      m.to("EXECUTE_READ_TOOLS");
      while (step && m.remainingTools() > 0) {
        (ev as Record<string, unknown>)[step.slot] = sanitize(await tool(c, step.name, step.args), c.machine);
        const next = impl.plan(c, ev, m.iterations);
        if (!next || next.slot === step.slot) break;
        step = next;
      }
      m.to("EVALUATE_EVIDENCE");
      const more = impl.plan(c, ev, m.iterations);
      if (impl.sufficient(ev) || !more || m.iterations >= m.budget.maxIterations || m.remainingTools() <= 0 || m.expired()) {
        m.to("DRAFT_RESPONSE");
        break;
      }
    }
    composed = impl.compose(c, ev);
    m.to("OUTPUT_GUARD");
    const unsafe = (b: Block) => (b.type === "text" || b.type === "notice") && !explanationIsSafe(b.text);
    if (composed.blocks.some(unsafe)) {
      if (m.retryGuard()) {
        m.to("DRAFT_RESPONSE", "guard_retry");
        const kept = composed.blocks.filter((b) => !unsafe(b));
        composed = { ...composed, blocks: kept.length ? kept : [{ type: "text", text: "Aku tidak dapat menyusun jawaban yang aman untuk ini. Tanyakan ke tenaga kesehatanmu." }] };
        m.to("OUTPUT_GUARD");
      }
      if (composed.blocks.some(unsafe)) {
        composed = { blocks: [{ type: "text", text: "Aku tidak dapat menyusun jawaban yang aman untuk ini. Tanyakan ke tenaga kesehatanmu." }], certainty: "unknown", sources: [] };
        m.to("BLOCKED", "output_guard");
        status = "BLOCKED";
      } else m.to("COMPLETED");
    } else m.to("COMPLETED");
  } catch (e) {
    if (!(e instanceof FsmError)) throw e;
    if (m.state !== "FAILED") m.to("FAILED", e.code);
    status = "FAILED";
    composed = { blocks: [{ type: "text", text: "Terjadi kendala saat menyusun jawaban. Coba lagi sebentar lagi." }], certainty: "unknown", sources: [] };
  }
  const result: SkillResult = {
    runId: run.id,
    skillId: skill.id,
    status,
    blocks: composed.blocks,
    certainty: composed.certainty,
    memoryIds: ev.memory?.ids ?? [],
    sources: composed.sources,
    fsm: { state: m.state, iterations: m.iterations, toolCalls: m.toolCalls, path: ["RECEIVED", ...m.history.map((h) => h.to)] },
  };
  await persistEvents(run.id, m, { skillId: skill.id, certainty: result.certainty, memoryIds: result.memoryIds, shadowPlanner: shadowOn }, shadow);
  await prisma.agentRun.update({ where: { id: run.id }, data: { status, fsmState: m.state, iterations: m.iterations, toolCallsUsed: m.toolCalls, state: { result } as unknown as Prisma.InputJsonObject } });
  return result;
}
