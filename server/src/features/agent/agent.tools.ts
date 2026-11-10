import { createHash } from "node:crypto";
import { z } from "zod";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { ACTIVITY_COUNTED_QUALITY } from "../activity/activity.model.ts";
import { foodPreferencesService } from "../food-preferences/food-preferences.service.ts";
import { referenceService } from "../food-reference/reference.service.ts";
import { goalsService } from "../goals/goals.service.ts";
import { nutritionService } from "../nutrition/nutrition.service.ts";
import { personalization } from "./personalization.ts";

/**
 * Registri alat deny-by-default. Alat hanya yang terdaftar di sini; tidak ada SQL, shell, URL bebas, atau akses akun lain.
 * `userId` SELALU berasal dari run milik sesi, tidak pernah dari argumen yang dibuat model/klien.
 */
export type ToolContext = { userId: string; runId: string; intent: string; maxCalls: number; callsUsed: number };

type Tool<I, O> = {
  name: string;
  version: string;
  purpose: string;
  input: z.ZodType<I>;
  allowedIntents: string[];
  requiredPermissions: string[];
  timeoutMs: number;
  maxResultBytes: number;
  run(userId: string, args: I): Promise<O>;
};

const food = z.object({ query: z.string().trim().min(2).max(80), limit: z.number().int().min(1).max(12).default(8) }).strict();

const tools = {
  get_food_preferences: {
    name: "get_food_preferences",
    version: "1",
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
    purpose: "Tujuan perilaku aktif milik pengguna (judul, jenis, target).",
    input: z.object({}).strict(),
    allowedIntents: ["ACTIVITY_PLAN"],
    requiredPermissions: ["health_data_processing"],
    timeoutMs: 8000,
    maxResultBytes: 30_000,
    run: async (userId: string) => ((await goalsService.list(userId, { status: "active", limit: 20 })).items as any[]).map((g) => ({ id: g.id, title: g.title, goalType: g.goalType, target: g.targetValue, period: g.period })),
  } satisfies Tool<{}, unknown>,
} as const;

export type ToolName = keyof typeof tools;
export const TOOL_CONTRACTS = Object.values(tools).map((t) => ({ name: t.name, version: t.version, purpose: t.purpose, allowedIntents: t.allowedIntents, requiredPermissions: t.requiredPermissions, timeoutMs: t.timeoutMs, maxResultBytes: t.maxResultBytes }));

export class ToolError extends Error {
  constructor(readonly code: "UNKNOWN_TOOL" | "INTENT_NOT_ALLOWED" | "BUDGET_EXCEEDED" | "INVALID_ARGUMENTS" | "TIMEOUT" | "RESULT_TOO_LARGE" | "TOOL_FAILED", message: string) {
    super(message);
  }
}

const sha = (v: unknown) => createHash("sha256").update(JSON.stringify(v ?? null)).digest("hex");

async function record(ctx: ToolContext, tool: string, version: string, args: unknown, status: "OK" | "ERROR" | "DENIED" | "TIMEOUT", started: number, errorCode?: string, size = 0) {
  await prisma.agentToolCall.create({ data: { runId: ctx.runId, tool: tool.slice(0, 60), toolVersion: version, argsHash: sha(args), status, errorCode, durationMs: Math.min(Date.now() - started, 2_000_000), resultSize: size } });
}

/** Satu-satunya jalur menjalankan alat. Semua penolakan juga dicatat. */
export async function executeTool<T = unknown>(ctx: ToolContext, name: string, rawArgs: unknown): Promise<T> {
  const started = Date.now();
  const tool = (tools as Record<string, Tool<any, unknown>>)[name];
  if (!tool) {
    await record(ctx, name, "-", rawArgs, "DENIED", started, "UNKNOWN_TOOL");
    throw new ToolError("UNKNOWN_TOOL", "Alat tidak terdaftar.");
  }
  if (!tool.allowedIntents.includes(ctx.intent)) {
    await record(ctx, name, tool.version, rawArgs, "DENIED", started, "INTENT_NOT_ALLOWED");
    throw new ToolError("INTENT_NOT_ALLOWED", "Alat tidak diizinkan untuk maksud ini.");
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
    await record(ctx, name, tool.version, parsed.data, "OK", started, undefined, size);
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
