import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { AppError, conflict, notFound, unprocessable } from "../../shared/errors/app-error.ts";
import type { RecommendationPayload } from "../agent/agent.graph.ts";
import { agentService } from "../agent/agent.service.ts";
import { identityMatch, identityTokens } from "../agent/food-identity.ts";
import { coachingService } from "../coaching/coaching.service.ts";
import { communityService } from "../community/community.service.ts";
import { consentService } from "../consent/consent.service.ts";
import { statisticsService } from "../insights/statistics.service.ts";
import { mealDraftService, type DraftInputItem } from "../meal-drafts/meal-draft.service.ts";
import { parseMealText, sanitizePhotoName } from "../meal-drafts/meal-text.parser.ts";
import { activityConstraintsFrom } from "../memory/memory.extract.ts";
import { memoryService } from "../memory/memory.service.ts";
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
  type Basis,
  type BasisSource,
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
type Reply = { parts: Part[]; route: string; runId: string | null; continuesRun: boolean; basis?: Basis | null };

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

const SAFETY_SOURCE: BasisSource = { kind: "SAFETY_POLICY", label: "Aturan keselamatan beOkay" };

function runBasis(run: RunView): Basis {
  const sources: BasisSource[] = [];
  const events = run.events as { type: string; payload: Record<string, unknown> }[];
  const ctx = events.find((e) => e.type === "CONTEXT_READY")?.payload ?? {};
  if (run.intent === "ACTIVITY_PLAN") {
    const sessions = Number(ctx.sessions ?? 0);
    sources.push({ kind: "ACTIVITY_HISTORY", label: sessions > 0 ? `Riwayat aktivitas 28 hari (${sessions} sesi)` : "Riwayat aktivitas 28 hari (belum ada sesi)" });
    if (Number(ctx.goals ?? 0) > 0) sources.push({ kind: "GOALS", label: `Tujuan aktifmu (${ctx.goals})` });
    sources.push({ kind: "SAFETY_POLICY", label: "Durasi tidak melebihi sesi terpanjangmu" });
  } else if (run.intent === "NUTRITION_ALTERNATIVES") {
    const summary = run.summary as unknown as { coverage?: { reference?: string; userCatalog?: string } | null; preferencesConsidered?: number };
    if (summary.coverage?.reference && summary.coverage.reference !== "UNAVAILABLE") sources.push({ kind: "FOOD_REFERENCE", label: "Tabel Komposisi Pangan Indonesia" });
    if (summary.coverage?.userCatalog === "OK") sources.push({ kind: "USER_CATALOG", label: "Katalog makananmu" });
    if ((summary.preferencesConsidered ?? 0) > 0) sources.push({ kind: "FOOD_PREFERENCES", label: "Preferensi dan alergi makananmu" });
    sources.push(SAFETY_SOURCE);
  } else if (run.status === "BLOCKED") {
    sources.push(SAFETY_SOURCE);
  }
  return { sources, memories: [] };
}

async function agentReply(
  userId: string,
  clientMessageId: string,
  message: string,
  opts: { query?: string; previousRunId?: string | null; route: string; intent?: "NUTRITION_ALTERNATIVES" | "ACTIVITY_PLAN"; activity?: { maxMinutes?: number; avoidTypes?: ("walking" | "cycling" | "running" | "strength")[] } },
): Promise<Reply> {
  try {
    const run = await agentService.createRun(userId, {
      idempotencyKey: `conv-${clientMessageId}`,
      message: message.slice(0, 2000),
      ...(opts.query ? { query: opts.query.slice(0, 80) } : {}),
      ...(opts.previousRunId ? { previousRunId: opts.previousRunId } : {}),
      ...(opts.intent ? { intent: opts.intent } : {}),
      ...(opts.activity && Object.keys(opts.activity).length ? { activity: opts.activity } : {}),
    });
    const reply = runReply(run, opts.query ?? null, opts.route === "FOLLOW_UP");
    return { ...reply, route: opts.route === "FOLLOW_UP" ? "FOLLOW_UP" : reply.route, basis: runBasis(run) };
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
    const domainLabel = { activity: "aktivitas", glucose: "glukosa", nutrition: "makan", medication: "obat", logging: "catatan" }[route.domain];
    return {
      parts: statisticsReply(route.domain, route.days, result.statistics, result.glucoseUnit),
      route: "STATS",
      runId: null,
      continuesRun: false,
      basis: { sources: [{ kind: "STATISTICS", label: `Ringkasan ${domainLabel} ${route.days} hari dari catatanmu` }], memories: [] },
    };
  } catch (e) {
    if (e instanceof AppError && e.code === "CONSENT_REQUIRED") return { parts: consentReply(String(e.details?.purpose ?? "descriptive_summaries")), route: "STATS", runId: null, continuesRun: false };
    throw e;
  }
}

const ACTIVITY_TYPES = new Set(["walking", "cycling", "running", "strength"]);

async function activityReply(userId: string, msg: Message, body: string, route: Extract<Route, { kind: "ACTIVITY_PLAN" }> | null, followUp: { previousRunId: string | null } | null): Promise<Reply> {
  const memories = await memoryService.activeFor(userId);
  const fromMemory = activityConstraintsFrom(memories);
  const explicit = route?.maxMinutes;
  const maxMinutes = explicit ?? fromMemory.maxMinutes;
  const avoidTypes = fromMemory.avoidTypes.filter((t) => ACTIVITY_TYPES.has(t)) as ("walking" | "cycling" | "running" | "strength")[];
  const activity = { ...(avoidTypes.length ? { avoidTypes } : {}), ...(maxMinutes ? { maxMinutes } : {}) };
  const reply = followUp
    ? await agentReply(userId, msg.clientMessageId!, body, { previousRunId: followUp.previousRunId, route: "FOLLOW_UP", activity })
    : await agentReply(userId, msg.clientMessageId!, body, { route: "ACTIVITY_PLAN", intent: "ACTIVITY_PLAN", activity });
  const offered = reply.parts.some((p) => p.type === "recommendations" && p.kind === "ACTIVITY");
  if (!offered) return reply;
  const used = memories.filter(
    (m) =>
      m.kind === "ACTIVITY_TIME" ||
      m.kind === "SCHEDULE" ||
      (m.kind === "ACTIVITY_DISLIKE" && avoidTypes.includes(m.key.split(":")[1] as never)) ||
      (m.kind === "AVAILABLE_MINUTES" && explicit === undefined && maxMinutes !== undefined),
  );
  const notes: Part[] = [];
  if (route?.busy) notes.push(text("Kalau sedang sibuk, ini versi singkatnya."));
  const time = used.find((m) => m.kind === "ACTIVITY_TIME");
  if (time) notes.push(text(`Aku ingat kamu ${time.content.charAt(0).toLowerCase()}${time.content.slice(1)}, jadi coba sisihkan waktu itu.`));
  const parts = [...reply.parts];
  parts.splice(1, 0, ...notes);
  return { ...reply, parts, basis: { sources: reply.basis?.sources ?? [], memories: used.map((m) => ({ id: m.id, content: m.content })) } };
}

function photoItems(msg: Message): DraftInputItem[] {
  const photo = (msg.parts as Part[]).find((p) => p.type === "photo");
  if (!photo || photo.type !== "photo") return [];
  return photo.items
    .map((i) => ({ name: sanitizePhotoName(i.name), confidence: i.confidence }))
    .filter((i) => i.name.length >= 2)
    .map((i) => ({ text: i.name, name: i.name, quantity: 1, unit: "portion" as const, unitLabel: null, quantityStated: false, grams: null, photoConfidence: i.confidence }));
}

async function mealDraftReply(userId: string, thread: Thread, body: string, msg: Message, fromPhoto: boolean): Promise<Reply> {
  const items = fromPhoto ? photoItems(msg) : parseMealText(body).items;
  const category = fromPhoto ? null : parseMealText(body).category;
  const route = fromPhoto ? "PHOTO_MEAL" : "MEAL_LOG";
  if (items.length === 0) {
    return {
      parts: [text(fromPhoto ? "Aku belum bisa mengenali makanan dari foto itu. Tulis saja namanya, misalnya \"nasi dan ayam bakar\"." : "Makanan apa saja yang kamu makan? Tulis namanya, misalnya \"nasi satu piring dan ayam bakar\".")],
      route,
      runId: null,
      continuesRun: false,
    };
  }
  const draft = await mealDraftService.propose(userId, { threadId: thread.id, source: fromPhoto ? "PHOTO" : "TEXT", text: fromPhoto ? null : body, category, items });
  const missing = draft.items.filter((i) => i.candidates.length === 0).length;
  const lead = fromPhoto
    ? "Dari foto, ini dugaan makanannya. Foto tidak bisa menentukan porsi, jadi periksa nama dan beratnya sebelum menyimpan."
    : "Ini draf catatan makanmu. Periksa porsinya dulu; belum ada yang tersimpan.";
  const sources: BasisSource[] = [fromPhoto ? { kind: "PHOTO", label: "Nama makanan dari foto (perkiraan model)" } : { kind: "MESSAGE", label: "Teks pesanmu" }];
  if (draft.items.some((i) => i.candidates.some((c) => c.kind === "TKPI"))) sources.push({ kind: "FOOD_REFERENCE", label: "Tabel Komposisi Pangan Indonesia" });
  if (draft.items.some((i) => i.candidates.some((c) => c.kind === "CATALOG"))) sources.push({ kind: "USER_CATALOG", label: "Katalog makananmu" });
  if (draft.items.some((i) => i.gramsBasis === "user_estimate")) sources.push({ kind: "PORTION_MEASURES", label: "Takaran porsi yang pernah kamu simpan" });
  return {
    parts: [text(lead), { type: "meal_draft", draftId: draft.id }, ...(missing > 0 ? [text(`${missing} makanan belum ditemukan di referensi; tetap bisa dicatat tanpa nilai gizi.`)] : [])],
    route,
    runId: null,
    continuesRun: false,
    basis: { sources, memories: [] },
  };
}

const COMMUNITY_RULES_TEXT =
  "Cara kerja tantangan: hari aktif = satu sesi aktivitas tercatat minimal 10 menit atau check-in kebiasaan. Satu hari dihitung sekali dan hari istirahat tidak mengurangi skor. Tidak ada poin untuk intensitas, gula darah, atau nilai kesehatan lain. Anggota lain hanya melihat aliasmu, dan skormu hanya tampil di papan peringkat bila kamu menyalakannya.";

async function communityReply(userId: string, topic: "DISCOVER" | "RULES" | "PROGRESS"): Promise<Reply> {
  const out = (parts: Part[]): Reply => ({ parts, route: "COMMUNITY", runId: null, continuesRun: false, basis: { sources: [{ kind: "GOALS", label: "Tantangan di komunitasmu" }], memories: [] } });
  const community: Part = { type: "link", label: "Buka Komunitas", target: "COMMUNITY" };
  if (topic === "RULES") return out([text(COMMUNITY_RULES_TEXT), community]);
  const s = await communityService.chatSuggestions(userId);
  if (s.consentRequired) return out([text("Komunitas bersifat opsional dan memakai alias, bukan namamu."), ...consentReply("community_membership"), community]);
  if (s.joinedCommunities === 0) return out([text("Kamu belum bergabung dengan komunitas. Pilih provinsimu lalu gabung dengan alias. Data kesehatanmu tidak pernah dibagikan."), community]);
  const item = (c: (typeof s.items)[number]) => {
    const mine = s.mine.find((m) => m.id === c.id);
    return { id: c.id, title: c.title, communityName: c.communityName, startsOn: c.startsOn, endsOn: c.endsOn, status: c.status, statusLabel: c.statusLabel, participating: c.participating, progress: mine ? { activeDays: mine.activeDays, targetDays: mine.targetDays } : null };
  };
  if (topic === "PROGRESS") {
    if (s.mine.length === 0) return out([text("Kamu belum ikut tantangan yang sedang berjalan atau akan dimulai."), ...(s.items.length ? [{ type: "challenges" as const, items: s.items.map(item) }] : []), community]);
    const lines = s.mine.map((m) => `${m.title}: ${m.activeDays} dari ${m.targetDays} hari aktif (${m.statusLabel.toLowerCase()}).`);
    return out([text(["Progres tantanganmu dari catatan:", ...lines, "Hari tanpa catatan bukan kegagalan; skor hanya bertambah."].join(" ")), { type: "challenges", items: s.items.filter((c) => c.participating).map(item) }]);
  }
  const open = s.items.filter((c) => !c.participating);
  if (open.length === 0) return out([text("Semua tantangan yang terbuka di komunitasmu sudah kamu ikuti. Kalau mau, buat tujuan pribadi yang tidak dibagikan ke siapa pun."), { type: "link", label: "Buat tujuan pribadi", target: "GOALS" }]);
  return out([
    text("Ini tantangan di komunitasmu yang bisa kamu ikuti. Kamu baru ikut setelah mengonfirmasi di halaman tantangan."),
    { type: "challenges", items: open.map(item) },
    { type: "link", label: "Buat tujuan pribadi", target: "GOALS" },
  ]);
}

async function reflectionReply(userId: string): Promise<Reply> {
  const open = await coachingService.reflection(userId);
  if (open.consentRequired) {
    return { parts: [text("Wajar merasa begitu. Satu minggu yang berat tidak membuatmu gagal."), ...consentReply("descriptive_summaries")], route: "REFLECTION", runId: null, continuesRun: false };
  }
  const now = open.isCurrentWeek ? open : await coachingService.reflection(userId, new Date(), { currentWeek: true });
  if (now.consentRequired) return { parts: consentReply("descriptive_summaries"), route: "REFLECTION", runId: null, continuesRun: false };
  const positives = now.positives.slice(0, 3);
  const actionsDone = now.actions.observed + now.actions.confirmed + now.actions.fromAssistant;
  const lead = positives.length
    ? `Wajar merasa begitu, dan satu minggu yang berat tidak membuatmu gagal. Ini yang benar-benar tercatat minggu ini${open.isCurrentWeek ? "" : " sejauh ini"}:`
    : "Wajar merasa begitu. Minggu ini belum banyak yang tercatat, dan itu tidak apa-apa. Kita bisa mulai lagi dari langkah yang sangat kecil.";
  const ask = open.done
    ? "Refleksi mingguanmu sudah terisi. Bagian mana yang paling berat? Ceritakan saja, atau lihat lagi rencanamu."
    : open.adjustments.length
      ? "Bagian mana yang paling berat? Kalau mau, target minggu depan bisa kita kecilkan bersama lewat refleksi mingguan."
      : "Bagian mana yang paling berat? Di refleksi mingguan kita bisa memilih satu langkah kecil untuk minggu depan.";
  const sources: BasisSource[] = [{ kind: "STATISTICS", label: `Ringkasan minggu ${now.weekStart} dari catatanmu` }];
  if (now.goals.length) sources.push({ kind: "GOALS", label: "Tujuan yang kamu pilih" });
  return {
    parts: [text(lead), { type: "reflection", weekStart: open.weekStart, positives, actionsDone, canAdjust: open.adjustments.length > 0, done: Boolean(open.done) }, text(ask)],
    route: "REFLECTION",
    runId: null,
    continuesRun: false,
    basis: { sources, memories: [] },
  };
}

async function compose(userId: string, thread: Thread, msg: Message): Promise<Reply> {
  const body = msg.text!;
  if ((msg.parts as Part[]).some((p) => p.type === "photo")) return mealDraftReply(userId, thread, body, msg, true);
  const context = (thread.context ?? {}) as { lastRoute?: string };
  const route = routeMessage(body, { hasPreviousRun: thread.lastRunId !== null, lastRoute: context.lastRoute ?? null });
  const fixed = (parts: Part[], basis: Basis | null = null): Reply => ({ parts, route: route.kind, runId: null, continuesRun: false, basis });
  switch (route.kind) {
    case "SAFETY":
      return fixed(safetyReply(route.code, route.message, route.urgent), { sources: [SAFETY_SOURCE], memories: [] });
    case "GREETING":
      return fixed(GREETING_REPLY);
    case "THANKS":
      return fixed(THANKS_REPLY);
    case "SUPPORT":
      return fixed(SUPPORT_REPLY);
    case "REFLECTION":
      return reflectionReply(userId);
    case "COMMUNITY":
      return communityReply(userId, route.topic);
    case "HELP":
      return fixed(HELP_REPLY);
    case "CLARIFY_FOOD":
      return fixed(CLARIFY_FOOD_REPLY);
    case "NO_CONTEXT":
      return fixed(NO_CONTEXT_REPLY);
    case "APPROVAL_HINT":
      return fixed([text("Ketuk “Tambahkan ke rencana” pada pilihan yang kamu mau. Aku tidak menyimpan apa pun tanpa ketukan itu.")]);
    case "MEAL_LOG":
      return mealDraftReply(userId, thread, body, msg, false);
    case "STATS":
      return statsReply(userId, route);
    case "FOLLOW_UP":
      return context.lastRoute === "ACTIVITY_PLAN"
        ? activityReply(userId, msg, body, null, { previousRunId: thread.lastRunId })
        : agentReply(userId, msg.clientMessageId!, body, { previousRunId: thread.lastRunId, route: "FOLLOW_UP" });
    case "ACTIVITY_PLAN":
      return activityReply(userId, msg, body, route, null);
    case "FOOD":
      return agentReply(userId, msg.clientMessageId!, body, { query: route.query, route: "FOOD" });
    case "UNKNOWN":
      if (route.probe && (await probeFood(route.probe))) return agentReply(userId, msg.clientMessageId!, body, { query: route.probe, route: "FOOD" });
      return fixed(UNKNOWN_REPLY);
  }
}

const QUIET_ROUTES = new Set(["UNKNOWN", "NO_CONTEXT", "CLARIFY_FOOD", "HELP"]);

async function withMemory(userId: string, msg: Message, reply: Reply): Promise<Reply> {
  if (reply.route === "SAFETY" || reply.route === "PHOTO_MEAL") return reply;
  const proposals = await memoryService.propose(userId, msg.text ?? "", msg.id);
  if (proposals.length === 0) return reply;
  const parts: Part[] = QUIET_ROUTES.has(reply.route) ? [text("Baik. Mau aku ingat ini untuk saran berikutnya?")] : [...reply.parts];
  for (const p of proposals) parts.push({ type: "memory_proposal", memoryId: p.id });
  return { ...reply, parts, route: QUIET_ROUTES.has(reply.route) ? "PREFERENCE" : reply.route };
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
  const all = messages.flatMap((m) => m.parts as Part[]);
  const ids = all.flatMap((p) => (p.type === "recommendations" ? p.recommendationIds : []));
  const draftIds = all.flatMap((p) => (p.type === "meal_draft" ? [p.draftId] : []));
  const memoryIds = all.flatMap((p) => (p.type === "memory_proposal" ? [p.memoryId] : []));
  const allowed = ids.length ? await hasConsent(userId, "personalized_ai") : true;
  const [rows, drafts, memories] = await Promise.all([
    ids.length && allowed ? prisma.recommendation.findMany({ where: { id: { in: ids }, userId } }) : Promise.resolve([]),
    mealDraftService.viewsFor(userId, draftIds),
    memoryService.viewsFor(userId, memoryIds),
  ]);
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
    basis: (m.basis as Basis | null) ?? null,
    parts: (m.parts as Part[]).map((p) =>
      p.type === "recommendations"
        ? { ...p, hidden: !allowed, items: p.recommendationIds.map((id) => byId.get(id)).filter((x) => x !== undefined) }
        : p.type === "meal_draft"
          ? { ...p, draft: drafts.get(p.draftId) ?? null }
          : p.type === "memory_proposal"
            ? { ...p, memory: memories.get(p.memoryId) ?? null }
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
  const reply = await withMemory(userId, userMsg, await compose(userId, thread, userMsg));
  const offered = reply.parts.some((p) => p.type === "recommendations");
  const context = { lastRoute: reply.route, offered, turns: Math.min(((thread.context as { turns?: number } | null)?.turns ?? 0) + 1, 9999) };
  const assistant = await prisma.$transaction(async (tx) => {
    const t = await tx.conversationThread.update({
      where: { id: thread.id },
      data: { messageCount: { increment: 1 }, lastMessageAt: new Date(), context, ...(reply.continuesRun && reply.runId ? { lastRunId: reply.runId } : {}) },
    });
    return tx.conversationMessage.create({
      data: {
        threadId: thread.id,
        userId,
        seq: t.messageCount,
        role: "ASSISTANT",
        replyToId: userMsg.id,
        parts: reply.parts as unknown as Prisma.InputJsonArray,
        route: reply.route,
        routerVersion: ROUTER_VERSION,
        runId: reply.runId,
        ...(reply.basis && reply.basis.sources.length + reply.basis.memories.length > 0 ? { basis: reply.basis as unknown as Prisma.InputJsonObject } : {}),
      },
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
      const priorPhoto = (prior.parts as Part[]).find((p) => p.type === "photo");
      if (JSON.stringify(priorPhoto && priorPhoto.type === "photo" ? priorPhoto.items : null) !== JSON.stringify(input.photo?.items ?? null)) throw conflict("IDEMPOTENCY_CONFLICT", "clientMessageId dipakai untuk pesan lain.");
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
        return tx.conversationMessage.create({
          data: {
            threadId: thread.id,
            userId,
            seq: t.messageCount,
            role: "USER",
            clientMessageId: input.clientMessageId,
            text: input.text,
            ...(input.photo ? { parts: [{ type: "photo", items: input.photo.items }] as unknown as Prisma.InputJsonArray } : {}),
          },
        });
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
      await tx.mealDraft.updateMany({ where: { threadId: t.id, userId, status: "PROPOSED" }, data: { status: "DISCARDED", resolvedAt: new Date(), version: { increment: 1 } } });
      await tx.conversationThread.delete({ where: { id: t.id } });
      await recordAudit(tx, { userId, eventType: "conversation_deleted", metadata: { threadId: t.id, messages: t.messageCount, runs: runIds.length } });
      return t.messageCount;
    });
    return { deleted: true, id, messages: deleted };
  },
};
