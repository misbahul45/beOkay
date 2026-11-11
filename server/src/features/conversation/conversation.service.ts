import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { AppError, conflict, notFound, unprocessable } from "../../shared/errors/app-error.ts";
import type { RecommendationPayload } from "../agent/agent.graph.ts";
import { agentService } from "../agent/agent.service.ts";
import { identityMatch, identityTokens } from "../agent/food-identity.ts";
import { consentService } from "../consent/consent.service.ts";
import { statisticsService } from "../insights/statistics.service.ts";
import {
  CLARIFY_FOOD_REPLY,
  GREETING_REPLY,
  HELP_REPLY,
  NO_CONTEXT_REPLY,
  SUPPORT_REPLY,
  THANKS_REPLY,
  UNKNOWN_REPLY,
  consentReply,
  safetyReply,
  statisticsReply,
  suggestions,
  text,
  type Part,
} from "./conversation.parts.ts";
import { ROUTER_VERSION, routeMessage, type Route } from "./conversation.router.ts";
import type { MessageCreate } from "./conversation.schema.ts";

export const MAX_MESSAGES = 400;
export const IN_PROGRESS_MS = 60_000;
const RATE_WINDOW_MS = 10 * 60_000;
const RATE_MAX = 30;
const rate = new Map<string, number[]>();
const REDACTED = "(percakapan dihapus)";

type Thread = NonNullable<Awaited<ReturnType<typeof prisma.conversationThread.findFirst>>>;
type Message = NonNullable<Awaited<ReturnType<typeof prisma.conversationMessage.findFirst>>>;
type RunView = Awaited<ReturnType<typeof agentService.getRun>>;
type Reply = { parts: Part[]; route: Route["kind"]; runId: string | null; continuesRun: boolean };

const hasConsent = async (userId: string, purpose: "personalized_ai" | "health_data_processing") => {
  try {
    await consentService.requireConsent(userId, purpose);
    return true;
  } catch {
    return false;
  }
};

const titleOf = (t: string) => {
  const one = t.replace(/\s+/g, " ").trim();
  return one.length <= 60 ? one : `${one.slice(0, 57).trimEnd()}…`;
};

async function probeFood(query: string): Promise<boolean> {
  const head = identityTokens(query)[0];
  if (!head) return false;
  const rows = await prisma.foodReference.findMany({ where: { status: "verified_auto", nameNormalized: { contains: head } }, select: { name: true }, take: 40 });
  return rows.some((r) => identityMatch(query, r.name) !== null);
}

function runReply(run: RunView, query: string | null, followUp: boolean): Reply {
  const recs = run.recommendations as { id: string; type: "NUTRITION" | "ACTIVITY"; candidate?: { match?: string } }[];
  const continues = ["NUTRITION_ALTERNATIVES", "ACTIVITY_PLAN"].includes(run.intent);
  if (run.consentRequired) return { parts: consentReply("personalized_ai"), route: "FOOD", runId: run.id, continuesRun: false };
  if (run.status === "BLOCKED") {
    return { parts: safetyReply(run.safetyDecision ?? "BLOCKED", run.message ?? "Permintaan ini di luar yang bisa kubantu.", run.safetyDecision === "URGENT_SYMPTOM"), route: "SAFETY", runId: run.id, continuesRun: false };
  }
  if (run.status === "FAILED") return { parts: [{ type: "notice", tone: "error", text: "Ada kendala saat menyusun jawaban. Catatanmu tidak terpengaruh. Coba lagi sebentar lagi." }], route: "FOOD", runId: run.id, continuesRun: false };
  if (recs.length > 0) {
    const kind = recs[0]!.type;
    const lead =
      kind === "ACTIVITY"
        ? "Ini pilihan aktivitas yang tidak melebihi kebiasaanmu. Belum ada yang tersimpan sampai kamu setujui."
        : recs[0]!.candidate?.match === "CLOSE"
          ? "Belum ada yang persis sama dengan pencarianmu. Ini yang paling mirip. Belum ada yang tersimpan sampai kamu setujui."
          : "Ini yang paling sesuai dengan pencarianmu. Belum ada yang tersimpan sampai kamu setujui.";
    return {
      parts: [
        text(lead),
        { type: "recommendations", runId: run.id, kind, recommendationIds: recs.map((r) => r.id) },
        suggestions([
          { label: "Kenapa yang ini?", message: "Kenapa ini disarankan?" },
          { label: "Cari yang lain", message: "Ada pilihan lain?" },
        ]),
      ],
      route: kind === "ACTIVITY" ? "ACTIVITY_PLAN" : "FOOD",
      runId: run.id,
      continuesRun: true,
    };
  }
  const state = run.summary as { query?: string | null };
  const message = run.message ?? "Belum ada hasil.";
  if (!followUp && run.intent === "NUTRITION_ALTERNATIVES" && (query ?? state.query)) {
    return { parts: [{ type: "no_match", query: (query ?? state.query)!, text: message }], route: "FOOD", runId: run.id, continuesRun: false };
  }
  return { parts: [text(message)], route: run.intent === "ACTIVITY_PLAN" ? "ACTIVITY_PLAN" : "FOLLOW_UP", runId: run.id, continuesRun: continues && run.intent !== "FOLLOW_UP_WHY" };
}

async function agentReply(userId: string, clientMessageId: string, message: string, opts: { query?: string; previousRunId?: string | null; route: Route["kind"] }): Promise<Reply> {
  try {
    const run = await agentService.createRun(userId, {
      idempotencyKey: `conv-${clientMessageId}`,
      message: message.slice(0, 2000),
      ...(opts.query ? { query: opts.query.slice(0, 80) } : {}),
      ...(opts.previousRunId ? { previousRunId: opts.previousRunId } : {}),
    });
    const reply = runReply(run, opts.query ?? null, opts.route === "FOLLOW_UP");
    return { ...reply, route: opts.route === "FOLLOW_UP" ? "FOLLOW_UP" : reply.route };
  } catch (e) {
    if (e instanceof AppError) {
      if (e.code === "CONSENT_REQUIRED") return { parts: consentReply(String(e.details?.purpose ?? "personalized_ai")), route: opts.route, runId: null, continuesRun: false };
      if (e.code === "AGENT_RATE_LIMITED") return { parts: [{ type: "notice", tone: "warning", text: "Terlalu banyak permintaan pencarian. Coba lagi beberapa menit lagi." }], route: opts.route, runId: null, continuesRun: false };
      if (e.code === "CONVERSATION_TOO_LONG" || e.code === "RUN_NOT_FOUND") return { parts: [text("Rangkaian pilihan ini sudah selesai. Tulis permintaan baru, misalnya \"cari info tempe\".")], route: opts.route, runId: null, continuesRun: false };
    }
    throw e;
  }
}

async function statsReply(userId: string, route: Extract<Route, { kind: "STATS" }>): Promise<Reply> {
  try {
    const result = await statisticsService.get(userId, route.days);
    return { parts: statisticsReply(route.domain, route.days, result.statistics, result.glucoseUnit), route: "STATS", runId: null, continuesRun: false };
  } catch (e) {
    if (e instanceof AppError && e.code === "CONSENT_REQUIRED") return { parts: consentReply(String(e.details?.purpose ?? "descriptive_summaries")), route: "STATS", runId: null, continuesRun: false };
    throw e;
  }
}

async function compose(userId: string, thread: Thread, msg: Message): Promise<Reply> {
  const body = msg.text!;
  const route = routeMessage(body, { hasPreviousRun: thread.lastRunId !== null });
  const fixed = (parts: Part[]): Reply => ({ parts, route: route.kind, runId: null, continuesRun: false });
  switch (route.kind) {
    case "SAFETY":
      return fixed(safetyReply(route.code, route.message, route.urgent));
    case "GREETING":
      return fixed(GREETING_REPLY);
    case "THANKS":
      return fixed(THANKS_REPLY);
    case "SUPPORT":
      return fixed(SUPPORT_REPLY);
    case "HELP":
      return fixed(HELP_REPLY);
    case "CLARIFY_FOOD":
      return fixed(CLARIFY_FOOD_REPLY);
    case "NO_CONTEXT":
      return fixed(NO_CONTEXT_REPLY);
    case "STATS":
      return statsReply(userId, route);
    case "FOLLOW_UP":
      return agentReply(userId, msg.clientMessageId!, body, { previousRunId: thread.lastRunId, route: "FOLLOW_UP" });
    case "ACTIVITY_PLAN":
      return agentReply(userId, msg.clientMessageId!, body, { route: "ACTIVITY_PLAN" });
    case "FOOD":
      return agentReply(userId, msg.clientMessageId!, body, { query: route.query, route: "FOOD" });
    case "UNKNOWN":
      if (route.probe && (await probeFood(route.probe))) return agentReply(userId, msg.clientMessageId!, body, { query: route.probe, route: "FOOD" });
      return fixed(UNKNOWN_REPLY);
  }
}

type RecRow = NonNullable<Awaited<ReturnType<typeof prisma.recommendation.findFirst>>>;
function recommendationItem(r: RecRow, now: number) {
  const p = r.payload as unknown as RecommendationPayload & { textSource?: string; activity?: { type: string; durationMinutes: number; label?: string } };
  return {
    id: r.id,
    version: r.version,
    status: r.status === "OFFERED" && r.expiresAt.getTime() < now ? "EXPIRED" : r.status,
    type: r.recType,
    name: p.candidate.name,
    match: p.candidate.match ?? null,
    source: p.candidate.source,
    provenance: p.candidate.provenance,
    completeness: p.candidate.completeness,
    per100g: p.candidate.per100g,
    activity: p.activity ?? null,
    explanation: p.explanation,
    rankingReason: p.rankingReason,
    limitations: p.limitations,
    writtenByModel: p.textSource === "LLM",
    expiresAt: r.expiresAt.toISOString(),
  };
}

async function hydrate(userId: string, messages: Message[]) {
  const ids = messages.flatMap((m) => (m.parts as Part[]).flatMap((p) => (p.type === "recommendations" ? p.recommendationIds : [])));
  const allowed = ids.length ? await hasConsent(userId, "personalized_ai") : true;
  const rows = ids.length && allowed ? await prisma.recommendation.findMany({ where: { id: { in: ids }, userId } }) : [];
  const now = Date.now();
  const byId = new Map(rows.map((r) => [r.id, recommendationItem(r, now)]));
  return messages.map((m) => ({
    id: m.id,
    seq: m.seq,
    role: m.role,
    clientMessageId: m.clientMessageId,
    replyToId: m.replyToId,
    text: m.text,
    route: m.route,
    createdAt: m.createdAt.toISOString(),
    parts: (m.parts as Part[]).map((p) =>
      p.type === "recommendations"
        ? { ...p, hidden: !allowed, items: p.recommendationIds.map((id) => byId.get(id)).filter((x) => x !== undefined) }
        : p,
    ),
  }));
}

const threadView = (t: Thread) => ({
  id: t.id,
  title: t.title,
  messageCount: t.messageCount,
  lastMessageAt: t.lastMessageAt?.toISOString() ?? null,
  createdAt: t.createdAt.toISOString(),
});

async function ownThread(userId: string, id: string) {
  const t = await prisma.conversationThread.findFirst({ where: { id, userId } });
  if (!t) throw notFound("THREAD_NOT_FOUND", "Percakapan tidak ditemukan.");
  return t;
}

async function ensureThread(userId: string, id: string, firstText: string): Promise<Thread> {
  const found = await prisma.conversationThread.findUnique({ where: { id } });
  if (found) {
    if (found.userId !== userId) throw notFound("THREAD_NOT_FOUND", "Percakapan tidak ditemukan.");
    return found;
  }
  try {
    const created = await prisma.conversationThread.create({ data: { id, userId, title: titleOf(firstText) } });
    await recordAudit(prisma, { userId, eventType: "conversation_created", metadata: { threadId: id } });
    return created;
  } catch (e) {
    if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") return ensureThread(userId, id, firstText);
    throw e;
  }
}

async function respond(userId: string, thread: Thread, userMsg: Message) {
  const reply = await compose(userId, thread, userMsg);
  const assistant = await prisma.$transaction(async (tx) => {
    const t = await tx.conversationThread.update({
      where: { id: thread.id },
      data: { messageCount: { increment: 1 }, lastMessageAt: new Date(), ...(reply.continuesRun && reply.runId ? { lastRunId: reply.runId } : {}) },
    });
    return tx.conversationMessage.create({
      data: { threadId: thread.id, userId, seq: t.messageCount, role: "ASSISTANT", replyToId: userMsg.id, parts: reply.parts as unknown as Prisma.InputJsonArray, route: reply.route, routerVersion: ROUTER_VERSION, runId: reply.runId },
    });
  });
  return assistant;
}

async function exchange(userId: string, threadId: string, userMsg: Message, assistant: Message, replayed: boolean) {
  const [u, a] = await hydrate(userId, [userMsg, assistant]);
  return { replayed, thread: threadView(await ownThread(userId, threadId)), userMessage: u!, assistantMessage: a! };
}

export const conversationService = {
  async list(userId: string) {
    await consentService.requireConsent(userId, "health_data_processing");
    const rows = await prisma.conversationThread.findMany({ where: { userId }, orderBy: [{ lastMessageAt: { sort: "desc", nulls: "last" } }, { createdAt: "desc" }], take: 30 });
    return { items: rows.map(threadView) };
  },

  async get(userId: string, id: string) {
    await consentService.requireConsent(userId, "health_data_processing");
    const t = await ownThread(userId, id);
    const messages = await prisma.conversationMessage.findMany({ where: { threadId: id, userId }, orderBy: { seq: "asc" } });
    return { thread: threadView(t), messages: await hydrate(userId, messages) };
  },

  async post(userId: string, threadId: string, input: MessageCreate) {
    await consentService.requireConsent(userId, "health_data_processing");
    const prior = await prisma.conversationMessage.findUnique({ where: { userId_clientMessageId: { userId, clientMessageId: input.clientMessageId } }, include: { reply: true } });
    if (prior) {
      if (prior.threadId !== threadId || prior.text !== input.text) throw conflict("IDEMPOTENCY_CONFLICT", "clientMessageId dipakai untuk pesan lain.");
      if (prior.reply) return exchange(userId, threadId, prior, prior.reply, true);
      if (Date.now() - prior.createdAt.getTime() < IN_PROGRESS_MS) throw conflict("MESSAGE_IN_PROGRESS", "Pesan sedang diproses. Coba lagi sebentar.");
      const thread = await ownThread(userId, threadId);
      return exchange(userId, threadId, prior, await respond(userId, thread, prior), false);
    }

    const now = Date.now();
    const recent = (rate.get(userId) ?? []).filter((x) => now - x < RATE_WINDOW_MS);
    if (recent.length >= RATE_MAX) {
      rate.set(userId, recent);
      throw new AppError(429, "CONVERSATION_RATE_LIMITED", "Terlalu banyak pesan. Coba lagi beberapa menit lagi.");
    }
    const thread = await ensureThread(userId, threadId, input.text);
    if (thread.messageCount + 2 > MAX_MESSAGES) throw unprocessable("THREAD_FULL", "Percakapan ini sudah panjang. Mulai percakapan baru.");
    rate.set(userId, [...recent, now]);

    let userMsg: Message;
    try {
      userMsg = await prisma.$transaction(async (tx) => {
        const t = await tx.conversationThread.update({ where: { id: thread.id }, data: { messageCount: { increment: 1 }, lastMessageAt: new Date() } });
        return tx.conversationMessage.create({ data: { threadId: thread.id, userId, seq: t.messageCount, role: "USER", clientMessageId: input.clientMessageId, text: input.text } });
      });
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") throw conflict("MESSAGE_IN_PROGRESS", "Pesan sedang diproses. Coba lagi sebentar.");
      throw e;
    }
    const fresh = await ownThread(userId, thread.id);
    return exchange(userId, threadId, userMsg, await respond(userId, fresh, userMsg), false);
  },

  async remove(userId: string, id: string) {
    const t = await ownThread(userId, id);
    const runIds = [...new Set((await prisma.conversationMessage.findMany({ where: { threadId: id, userId, runId: { not: null } }, select: { runId: true } })).map((m) => m.runId!))];
    const deleted = await prisma.$transaction(async (tx) => {
      if (runIds.length) {
        await tx.recommendation.updateMany({ where: { runId: { in: runIds }, userId, status: "OFFERED" }, data: { status: "INVALIDATED", version: { increment: 1 } } });
        await tx.agentRun.updateMany({ where: { id: { in: runIds }, userId, status: "WAITING_FOR_USER" }, data: { status: "CANCELLED", version: { increment: 1 } } });
        await tx.agentRun.updateMany({ where: { id: { in: runIds }, userId }, data: { inputText: REDACTED } });
      }
      await tx.conversationThread.delete({ where: { id: t.id } });
      await recordAudit(tx, { userId, eventType: "conversation_deleted", metadata: { threadId: t.id, messages: t.messageCount, runs: runIds.length } });
      return t.messageCount;
    });
    return { deleted: true, id, messages: deleted };
  },
};
