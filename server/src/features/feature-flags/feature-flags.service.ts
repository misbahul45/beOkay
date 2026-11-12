import type { Server } from "bun";
import { env } from "../../config/env.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { AppError } from "../../shared/errors/app-error.ts";
import { route } from "../../shared/http/handler.ts";

export const FEATURE_KEYS = ["assistant", "conversation", "coaching", "community", "ml_inference", "food_vision", "web_discovery", "analytics", "push", "llm_router", "companion", "cgm"] as const;
export type FeatureKey = (typeof FEATURE_KEYS)[number];

export const FEATURE_LABELS: Record<FeatureKey, string> = {
  assistant: "Asisten (saran)",
  conversation: "Percakapan Asisten",
  coaching: "Rencana kecil dan refleksi",
  community: "Komunitas dan tantangan",
  ml_inference: "Model pengenal makanan",
  food_vision: "Pemindaian label dan foto",
  web_discovery: "Pencarian makanan di luar aplikasi",
  analytics: "Analitik pemakaian",
  push: "Notifikasi push",
  llm_router: "Pemahaman pesan dengan model bahasa",
  companion: "Tautan pendamping",
  cgm: "Impor sensor glukosa (CGM)",
};

export const CACHE_MS = env.FEATURE_FLAG_CACHE_MS;

type Snapshot = { at: number; values: Map<string, boolean> };
let cache: Snapshot | null = null;

const envDefault = (key: FeatureKey) => !env.FEATURES_DISABLED.includes(key);

async function load(now: number): Promise<Map<string, boolean>> {
  if (cache && now - cache.at < CACHE_MS) return cache.values;
  try {
    const rows = await prisma.featureFlag.findMany();
    const values = new Map(rows.map((r) => [r.key, r.enabled]));
    cache = { at: now, values };
    return values;
  } catch {
    return cache?.values ?? new Map();
  }
}

export const featureFlags = {
  async isEnabled(key: FeatureKey, now = Date.now()): Promise<boolean> {
    const values = await load(now);
    return values.get(key) ?? envDefault(key);
  },

  async all(now = Date.now()) {
    const values = await load(now);
    return Object.fromEntries(FEATURE_KEYS.map((k) => [k, values.get(k) ?? envDefault(k)])) as Record<FeatureKey, boolean>;
  },

  async require(key: FeatureKey) {
    if (!(await this.isEnabled(key))) throw disabled(key);
  },

  async set(key: FeatureKey, enabled: boolean, by: string, note: string | null) {
    const before = await prisma.featureFlag.findUnique({ where: { key } });
    const row = await prisma.featureFlag.upsert({ where: { key }, create: { key, enabled, note, updatedBy: by }, update: { enabled, note, updatedBy: by } });
    await prisma.auditEvent.create({ data: { userId: null, eventType: "feature_flag_changed", metadata: { key, from: before?.enabled ?? envDefault(key), to: enabled, by, note } } });
    cache = null;
    return row;
  },

  async clear(key: FeatureKey, by: string) {
    const before = await prisma.featureFlag.findUnique({ where: { key } });
    if (!before) return null;
    await prisma.featureFlag.delete({ where: { key } });
    await prisma.auditEvent.create({ data: { userId: null, eventType: "feature_flag_changed", metadata: { key, from: before.enabled, to: envDefault(key), by, note: "reset ke nilai env" } } });
    cache = null;
    return before;
  },

  resetCache() {
    cache = null;
  },
};

function disabled(key: FeatureKey) {
  return new AppError(503, "FEATURE_DISABLED", "Fitur ini dimatikan sementara. Coba lagi nanti.", { feature: key });
}

type Handler = (req: Request, server: Server<unknown>) => Response | Promise<Response>;
type RouteTable = Record<string, Record<string, Handler> | Handler>;

export function gated<T extends RouteTable>(key: FeatureKey, routes: T): T {
  const blocked = route(async () => {
    throw disabled(key);
  });
  const wrap = (h: Handler): Handler => async (req, server) => ((await featureFlags.isEnabled(key)) ? h(req, server) : blocked(req, server));
  return Object.fromEntries(
    Object.entries(routes).map(([path, value]) => [
      path,
      typeof value === "function" ? wrap(value) : Object.fromEntries(Object.entries(value).map(([m, h]) => [m, wrap(h)])),
    ]),
  ) as T;
}
