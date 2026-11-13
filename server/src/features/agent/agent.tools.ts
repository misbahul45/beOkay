import { createHash } from "node:crypto";
import { z } from "zod";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { ACTIVITY_COUNTED_QUALITY } from "../activity/activity.model.ts";
import type { ConsentPurpose } from "../consent/consent.policy.ts";
import { consentService } from "../consent/consent.service.ts";
import { foodPreferencesService } from "../food-preferences/food-preferences.service.ts";
import { referenceService } from "../food-reference/reference.service.ts";
import { env } from "../../config/env.ts";
import { createFirecrawlClient } from "../food-discovery/firecrawl.client.ts";
import { foodNameFromTitle, parseNutritionPer100g } from "../food-discovery/web-nutrition.parser.ts";
import { goalsService } from "../goals/goals.service.ts";
import { nutritionService } from "../nutrition/nutrition.service.ts";
import { identityTokens } from "./food-identity.ts";
import { personalization } from "./personalization.ts";
import { cohortService } from "../cohort/cohort.service.ts";
import { deviceQualityService } from "../devices/quality.service.ts";
import { knowledgeService } from "../knowledge/knowledge.service.ts";
import { certaintyOf } from "../knowledge/knowledge.model.ts";
import { memoryService } from "../memory/memory.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { dailyFacts } from "../projections/daily-facts.service.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { GLOBAL_PROHIBITED } from "./skills/registry.ts";

/**
 * Registri alat deny-by-default. Alat hanya yang terdaftar di sini; tidak ada SQL, shell, URL bebas, atau akses akun lain.
 * `userId` SELALU berasal dari run milik sesi, tidak pernah dari argumen yang dibuat model/klien.
 */
export type ToolContext = { userId: string; runId: string; intent: string; maxCalls: number; callsUsed: number; allowedTools?: readonly string[]; iteration?: number; skillId?: string };

type Tool<I, O> = {
  name: string;
  version: string;
  tier: "READ_ONLY";
  purpose: string;
  input: z.ZodType<I>;
  allowedIntents: string[];
  requiredPermissions: ConsentPurpose[];
  timeoutMs: number;
  maxResultBytes: number;
  run(userId: string, args: I): Promise<O>;
};

const food = z.object({ query: z.string().trim().min(2).max(80), limit: z.number().int().min(1).max(12).default(8) }).strict();
const webFood = z.object({ query: z.string().trim().min(2).max(80), limit: z.number().int().min(1).max(5).default(4) }).strict();

export const webSearchRef: { current: Pick<ReturnType<typeof createFirecrawlClient>, "configured" | "search"> } = { current: createFirecrawlClient(env.FIRECRAWL_API_KEY) };

export type WebNutritionResult = { title: string; name: string; url: string; host: string; per100g: ReturnType<typeof parseNutritionPer100g> };

const tools = {
  get_food_preferences: {
    name: "get_food_preferences",
    version: "1",
    tier: "READ_ONLY",
    purpose: "Alergi, pembatasan, dan preferensi makanan aktif milik pengguna.",
    input: z.object({}).strict(),
    allowedIntents: ["NUTRITION_ALTERNATIVES"],
    requiredPermissions: ["health_data_processing"],
    timeoutMs: 5000,
    maxResultBytes: 20_000,
    run: (userId: string) => foodPreferencesService.activeFor(userId),
  } satisfies Tool<{}, unknown>,
  get_personalization: {
    name: "get_personalization",
    version: "1",
    tier: "READ_ONLY",
    purpose: "Profil personalisasi deterministik (kata makanan yang pernah ditolak) milik pengguna.",
    input: z.object({}).strict(),
    allowedIntents: ["NUTRITION_ALTERNATIVES", "ACTIVITY_PLAN"],
    requiredPermissions: ["personalized_ai"],
    timeoutMs: 5000,
    maxResultBytes: 20_000,
    run: (userId: string) => personalization.get(userId),
  } satisfies Tool<{}, unknown>,
  search_food_reference: {
    name: "search_food_reference",
    version: "1",
    tier: "READ_ONLY",
    purpose: "Pencarian hibrida pada referensi TKPI (verified_auto saja).",
    input: food,
    allowedIntents: ["NUTRITION_ALTERNATIVES"],
    requiredPermissions: ["health_data_processing"],
    timeoutMs: 10_000,
    maxResultBytes: 80_000,
    run: async (_userId: string, a: z.infer<typeof food>) => referenceService.search(a.query, a.limit),
  } satisfies Tool<z.infer<typeof food>, unknown>,
  search_user_foods: {
    name: "search_user_foods",
    version: "1",
    tier: "READ_ONLY",
    purpose: "Makanan di katalog milik pengguna dan katalog bersama.",
    input: food,
    allowedIntents: ["NUTRITION_ALTERNATIVES"],
    requiredPermissions: ["health_data_processing"],
    timeoutMs: 8000,
    maxResultBytes: 80_000,
    run: async (userId: string, a: z.infer<typeof food>) => (await nutritionService.searchFoods(userId, a.query)).items.slice(0, a.limit),
  } satisfies Tool<z.infer<typeof food>, unknown>,
  get_activity_context: {
    name: "get_activity_context",
    version: "1",
    tier: "READ_ONLY",
    purpose: "Riwayat sesi aktivitas 28 hari terakhir milik pengguna (jenis, durasi, sumber). Tidak mengandaikan jam tangan.",
    input: z.object({}).strict(),
    allowedIntents: ["ACTIVITY_PLAN"],
    requiredPermissions: ["health_data_processing"],
    timeoutMs: 8000,
    maxResultBytes: 60_000,
    run: async (userId: string) => {
      const since = new Date(Date.now() - 28 * 86_400_000);
      const rows = await prisma.activitySession.findMany({ where: { userId, archivedAt: null, qualityStatus: { in: [...ACTIVITY_COUNTED_QUALITY] }, startedAt: { gte: since } }, orderBy: { startedAt: "desc" }, take: 100, select: { activityType: true, durationMinutes: true, startedAt: true, source: true } });
      return { windowDays: 28, sessions: rows.map((r) => ({ type: r.activityType, minutes: r.durationMinutes, at: r.startedAt.toISOString(), source: r.source })), deviceSessions: rows.filter((r) => r.source !== "manual").length };
    },
  } satisfies Tool<{}, unknown>,
  get_behavior_goals: {
    name: "get_behavior_goals",
    version: "1",
    tier: "READ_ONLY",
    purpose: "Tujuan perilaku aktif milik pengguna (judul, jenis, target).",
    input: z.object({}).strict(),
    allowedIntents: ["ACTIVITY_PLAN", "BARRIER_SOLVING", "MEMORY_REFLECT"],
    requiredPermissions: ["health_data_processing"],
    timeoutMs: 8000,
    maxResultBytes: 30_000,
    run: async (userId: string) => ((await goalsService.list(userId, { status: "active", limit: 20 })).items as any[]).map((g) => ({ id: g.id, title: g.title, goalType: g.goalType, target: g.targetValue, period: g.period })),
  } satisfies Tool<{}, unknown>,
  search_web_nutrition: {
    name: "search_web_nutrition",
    version: "1",
    tier: "READ_ONLY",
    purpose: "Pencarian web (Firecrawl) untuk nilai gizi per 100 g bila referensi lokal tidak memuat makanannya. Hanya angka yang lolos parser deterministik yang dikembalikan; hasil belum diverifikasi.",
    input: webFood,
    allowedIntents: ["MEAL_DRAFT_ENRICHMENT"],
    requiredPermissions: ["health_data_processing"],
    timeoutMs: 25_000,
    maxResultBytes: 20_000,
    run: async (_userId: string, a: z.infer<typeof webFood>): Promise<WebNutritionResult[]> => {
      const pages = await webSearchRef.current.search(`${a.query} kandungan gizi per 100 gram`, a.limit);
      const anchor = identityTokens(a.query)[0];
      return pages.map((p) => ({ title: p.title, name: foodNameFromTitle(p.title), url: p.url, host: p.host, per100g: parseNutritionPer100g(p.markdown, anchor) }));
    },
  } satisfies Tool<z.infer<typeof webFood>, unknown>,
  get_daily_facts: {
    name: "get_daily_facts",
    version: "1",
    tier: "READ_ONLY",
    purpose: "Fakta perilaku harian dari proyeksi tunggal (hari, menit aktif, langkah, tidur, catatan). Data perangkat hanya bila persetujuan perangkat untuk saran diberikan.",
    input: z.object({ days: z.number().int().min(1).max(28).default(14) }).strict(),
    allowedIntents: ["ACTIVITY_PLAN", "SLEEP_RECOVERY", "TREND_EXPLAIN", "CHALLENGE_COACH", "MEMORY_REFLECT"],
    requiredPermissions: ["health_data_processing"],
    timeoutMs: 8000,
    maxResultBytes: 40_000,
    run: async (userId: string, a: { days: number }) => {
      const [{ timezone }, device] = await Promise.all([preferencesService.get(userId), consentService.hasConsent(userId, "device_data_coaching")]);
      const today = localRecordTime(new Date(), timezone).localDate;
      const from = new Date(Date.parse(today + "T00:00:00Z") - (a.days - 1) * 86_400_000).toISOString().slice(0, 10);
      const facts = await dailyFacts.list(userId, from, today, timezone);
      const observed = facts.filter((f) => f.sessionCount > 0 || f.mealsLogged > 0 || f.steps !== null || f.sleepMinutes !== null).length;
      return {
        windowDays: a.days,
        deviceDataIncluded: device,
        certainty: certaintyOf({ kind: "projection", observedDays: observed, windowDays: a.days }),
        days: facts.map((f) => ({ date: f.localDate, activeMinutes: device ? f.activeMinutes : f.activeMinutesManual, sessions: f.sessionCount, steps: device ? f.steps : null, sleepMinutes: device ? f.sleepMinutes : null, meals: f.mealsLogged, glucoseChecks: f.glucoseChecks, goalCheckins: f.goalCheckins })),
      };
    },
  } satisfies Tool<{ days: number }, unknown>,
  get_device_quality: {
    name: "get_device_quality",
    version: "1",
    tier: "READ_ONLY",
    purpose: "Ringkasan kualitas data perangkat 14 hari per sinyal (cakupan, konflik, basi). Tanpa nilai klinis.",
    input: z.object({}).strict(),
    allowedIntents: ["SLEEP_RECOVERY", "TREND_EXPLAIN"],
    requiredPermissions: ["health_data_processing"],
    timeoutMs: 8000,
    maxResultBytes: 20_000,
    run: async (userId: string) => {
      const q = await deviceQualityService.assess(userId, 14);
      return { version: q.version, signals: q.summary, lastSyncAt: q.lastSyncAt };
    },
  } satisfies Tool<{}, unknown>,
  search_knowledge: {
    name: "search_knowledge",
    version: "1",
    tier: "READ_ONLY",
    purpose: "Retrieval jalur A (bacaan kesehatan umum) atau C (strategi perilaku) yang sudah difilter jalur pengguna, bahasa, status tinjauan, dan kedaluwarsa. Abstain bila bukti tidak cukup.",
    input: z.object({ query: z.string().trim().min(2).max(160), lane: z.enum(["A_PUBLIC_HEALTH", "C_BEHAVIOR_STRATEGY"]), limit: z.number().int().min(1).max(5).default(3) }).strict(),
    allowedIntents: ["SLEEP_RECOVERY", "BARRIER_SOLVING", "PREVENTION_EDUCATION"],
    requiredPermissions: ["health_data_processing"],
    timeoutMs: 10_000,
    maxResultBytes: 30_000,
    run: async (userId: string, a: { query: string; lane: "A_PUBLIC_HEALTH" | "C_BEHAVIOR_STRATEGY"; limit: number }) => knowledgeService.retrieve({ query: a.query, lane: a.lane, journey: await cohortService.journeyOf(userId), limit: a.limit }),
  } satisfies Tool<{ query: string; lane: "A_PUBLIC_HEALTH" | "C_BEHAVIOR_STRATEGY"; limit: number }, unknown>,
  get_memory_context: {
    name: "get_memory_context",
    version: "1",
    tier: "READ_ONLY",
    purpose: "Ingatan terkonfirmasi yang relevan untuk skill ini (tidak dijeda, tidak kedaluwarsa), dibatasi anggaran butir.",
    input: z.object({ skillId: z.string().regex(/^[a-z]+\.[a-z_]+$/), budget: z.number().int().min(1).max(10).default(5) }).strict(),
    allowedIntents: ["NUTRITION_ALTERNATIVES", "ACTIVITY_PLAN", "BARRIER_SOLVING", "MEMORY_REFLECT"],
    requiredPermissions: ["personalized_ai"],
    timeoutMs: 5000,
    maxResultBytes: 20_000,
    run: async (userId: string, a: { skillId: string; budget: number }) => {
      const r = await memoryService.retrieve(userId, a.skillId, a.budget);
      return { ids: r.ids, withheld: r.withheld, items: r.items.map((m) => ({ id: m.id, kind: m.kind, type: m.memoryType, content: m.content, confirmedAt: m.confirmedAt?.toISOString() ?? null })) };
    },
  } satisfies Tool<{ skillId: string; budget: number }, unknown>,
} as const;

export const CONFIRMED_ACTIONS = {
  plan_meal: { tier: "USER_CONFIRMED", purpose: "Menyimpan pilihan makan ke rencana", via: "POST /api/me/agent/recommendations/:id/decision" },
  plan_activity: { tier: "USER_CONFIRMED", purpose: "Menyimpan aktivitas ke rencana", via: "POST /api/me/agent/recommendations/:id/decision" },
  save_food_preference: { tier: "USER_CONFIRMED", purpose: "Menyimpan preferensi makanan", via: "POST /api/me/food-preferences" },
  save_memory: { tier: "USER_CONFIRMED", purpose: "Menyimpan ingatan yang diusulkan", via: "POST /api/me/memories/:id/confirm" },
  join_challenge: { tier: "USER_CONFIRMED", purpose: "Ikut tantangan", via: "POST /api/me/challenges/:id/join" },
  adjust_goal: { tier: "USER_CONFIRMED", purpose: "Mengubah target lewat refleksi", via: "POST /api/me/coaching/checkins" },
  update_reminder: { tier: "USER_CONFIRMED", purpose: "Mengubah pengingat", via: "PATCH /api/me/reminders/:id" },
} as const;
export type ConfirmedAction = keyof typeof CONFIRMED_ACTIONS;

export const PROHIBITED_TOOLS: readonly string[] = GLOBAL_PROHIBITED;

export type ToolName = keyof typeof tools;
export const TOOL_NAMES: ReadonlySet<string> = new Set(Object.keys(tools));
export const TOOL_CONTRACTS = Object.values(tools).map((t) => ({ name: t.name, version: t.version, tier: t.tier, purpose: t.purpose, allowedIntents: t.allowedIntents, requiredPermissions: t.requiredPermissions, timeoutMs: t.timeoutMs, maxResultBytes: t.maxResultBytes }));

export class ToolError extends Error {
  constructor(readonly code: "UNKNOWN_TOOL" | "PROHIBITED" | "REQUIRES_CONFIRMATION" | "SKILL_TOOL_NOT_ALLOWED" | "INTENT_NOT_ALLOWED" | "PERMISSION_DENIED" | "BUDGET_EXCEEDED" | "INVALID_ARGUMENTS" | "TIMEOUT" | "RESULT_TOO_LARGE" | "TOOL_FAILED", message: string) {
    super(message);
  }
}

const sha = (v: unknown) => createHash("sha256").update(JSON.stringify(v ?? null)).digest("hex");

async function record(ctx: ToolContext, tool: string, version: string, args: unknown, status: "OK" | "ERROR" | "DENIED" | "TIMEOUT", started: number, errorCode?: string, size = 0, tier: string | null = null) {
  await prisma.agentToolCall.create({ data: { runId: ctx.runId, tool: tool.slice(0, 60), toolVersion: version, argsHash: sha(args), status, errorCode, durationMs: Math.min(Date.now() - started, 2_000_000), resultSize: size, tier, iteration: ctx.iteration ?? null } });
}

/** Satu-satunya jalur menjalankan alat. Semua penolakan juga dicatat. */
export async function executeTool<T = unknown>(ctx: ToolContext, name: string, rawArgs: unknown): Promise<T> {
  const started = Date.now();
  if (PROHIBITED_TOOLS.includes(name)) {
    await record(ctx, name, "-", rawArgs, "DENIED", started, "PROHIBITED", 0, "PROHIBITED");
    throw new ToolError("PROHIBITED", "Tindakan ini tidak pernah dijalankan asisten.");
  }
  if (name in CONFIRMED_ACTIONS) {
    await record(ctx, name, "-", rawArgs, "DENIED", started, "REQUIRES_CONFIRMATION", 0, "USER_CONFIRMED");
    throw new ToolError("REQUIRES_CONFIRMATION", "Tindakan ini hanya berjalan setelah kamu menyetujuinya.");
  }
  const tool = (tools as Record<string, Tool<any, unknown>>)[name];
  if (tool && ctx.allowedTools && !ctx.allowedTools.includes(name)) {
    await record(ctx, name, tool.version, rawArgs, "DENIED", started, "SKILL_TOOL_NOT_ALLOWED", 0, tool.tier);
    throw new ToolError("SKILL_TOOL_NOT_ALLOWED", "Alat ini tidak diizinkan untuk skill ini.");
  }
  if (!tool) {
    await record(ctx, name, "-", rawArgs, "DENIED", started, "UNKNOWN_TOOL");
    throw new ToolError("UNKNOWN_TOOL", "Alat tidak terdaftar.");
  }
  if (!tool.allowedIntents.includes(ctx.intent)) {
    await record(ctx, name, tool.version, rawArgs, "DENIED", started, "INTENT_NOT_ALLOWED");
    throw new ToolError("INTENT_NOT_ALLOWED", "Alat tidak diizinkan untuk maksud ini.");
  }
  for (const purpose of tool.requiredPermissions) {
    try {
      await consentService.requireConsent(ctx.userId, purpose);
    } catch {
      await record(ctx, name, tool.version, rawArgs, "DENIED", started, "PERMISSION_DENIED");
      throw new ToolError("PERMISSION_DENIED", "Persetujuan untuk alat ini belum diberikan.");
    }
  }
  if (ctx.callsUsed >= ctx.maxCalls) {
    await record(ctx, name, tool.version, rawArgs, "DENIED", started, "BUDGET_EXCEEDED");
    throw new ToolError("BUDGET_EXCEEDED", "Batas pemanggilan alat tercapai.");
  }
  const parsed = tool.input.safeParse(rawArgs ?? {});
  if (!parsed.success) {
    await record(ctx, name, tool.version, rawArgs, "DENIED", started, "INVALID_ARGUMENTS");
    throw new ToolError("INVALID_ARGUMENTS", "Argumen alat tidak valid.");
  }
  ctx.callsUsed++;
  try {
    const result = await Promise.race([
      tool.run(ctx.userId, parsed.data),
      new Promise<never>((_, reject) => setTimeout(() => reject(new ToolError("TIMEOUT", "Alat melewati batas waktu.")), tool.timeoutMs)),
    ]);
    const size = JSON.stringify(result ?? null).length;
    if (size > tool.maxResultBytes) {
      await record(ctx, name, tool.version, parsed.data, "ERROR", started, "RESULT_TOO_LARGE", size);
      throw new ToolError("RESULT_TOO_LARGE", "Hasil alat terlalu besar.");
    }
    await record(ctx, name, tool.version, parsed.data, "OK", started, undefined, size, tool.tier);
    return result as T;
  } catch (e) {
    if (e instanceof ToolError) {
      if (e.code === "TIMEOUT") await record(ctx, name, tool.version, parsed.data, "TIMEOUT", started, "TIMEOUT");
      throw e;
    }
    await record(ctx, name, tool.version, parsed.data, "ERROR", started, "TOOL_FAILED");
    throw new ToolError("TOOL_FAILED", "Alat gagal dijalankan.");
  }
}
