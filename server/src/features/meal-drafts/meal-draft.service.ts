import { createHash } from "node:crypto";
import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { AppError, conflict, notFound, unprocessable } from "../../shared/errors/app-error.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { executeTool, webSearchRef, type ToolContext, type WebNutritionResult } from "../agent/agent.tools.ts";
import { identityMatch, identityTokens } from "../agent/food-identity.ts";
import { consentService } from "../consent/consent.service.ts";
import { referenceService } from "../food-reference/reference.service.ts";
import { checkFood, type PreferenceLike } from "../food-preferences/food-preferences.model.ts";
import { foodPreferencesService } from "../food-preferences/food-preferences.service.ts";
import { numericNutrients } from "../nutrition/nutrition.model.ts";
import { mealCreateSchema } from "../nutrition/nutrition.schema.ts";
import { nutritionService } from "../nutrition/nutrition.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import type { DraftConfirm } from "./meal-draft.schema.ts";
import type { MealCategory, MealUnit, ParsedItem } from "./meal-text.parser.ts";

export const DRAFT_TTL_MS = 48 * 3_600_000;
const NUTRIENTS = ["calories", "carbohydrates", "protein", "fat", "fiber"] as const;

export type DraftCandidate = {
  key: string;
  kind: "TKPI" | "CATALOG" | "WEB";
  url?: string;
  host?: string;
  name: string;
  source: string;
  sourceVersion: string | null;
  per100g: Record<string, number | null>;
  completeness: "COMPLETE" | "PARTIAL" | "NONE";
  match: "EXACT" | "CLOSE";
  preference: "EXCLUDED" | "WARNING" | "NO_MATCH_FOUND";
};

export type DraftItem = {
  index: number;
  text: string;
  name: string;
  quantity: number;
  unit: MealUnit;
  unitLabel: string | null;
  quantityStated: boolean;
  grams: number | null;
  gramsBasis: "weighed" | "user_estimate" | null;
  photoConfidence: "high" | "medium" | "low" | null;
  candidates: DraftCandidate[];
  selected: string | null;
  webSearch?: { status: "FOUND" | "NONE" | "UNAVAILABLE"; at: string };
};

export type DraftInputItem = ParsedItem & { photoConfidence?: "high" | "medium" | "low" };

const completenessOf = (p: Record<string, number | null>): DraftCandidate["completeness"] => {
  const known = NUTRIENTS.filter((k) => p[k] !== null && p[k] !== undefined).length;
  return known === 5 ? "COMPLETE" : known === 0 ? "NONE" : "PARTIAL";
};
const num = (v: unknown): number | null => (v === null || v === undefined ? null : Number.isFinite(Number(v)) ? Number(v) : null);

export function zonedInstant(localDate: string, hhmm: string, timezone: string): Date {
  const [y, m, d] = localDate.split("-").map(Number) as [number, number, number];
  const [h, mi] = hhmm.split(":").map(Number) as [number, number];
  const target = Date.UTC(y, m - 1, d, h, mi);
  let guess = target;
  for (let i = 0; i < 3; i++) {
    const p = localRecordTime(new Date(guess), timezone);
    const [gy, gm, gd] = p.localDate.split("-").map(Number) as [number, number, number];
    const [gh, gmi] = p.localTime.split(":").map(Number) as [number, number];
    const shown = Date.UTC(gy, gm - 1, gd, gh, gmi);
    if (shown === target) break;
    guess += target - shown;
  }
  return new Date(guess);
}

const DEFAULT_TIME: Record<MealCategory, string | null> = { breakfast: "07:00", lunch: "12:30", dinner: "19:00", snack: null };

export function inferMealTime(category: MealCategory | null, now: Date, timezone: string): { category: MealCategory; consumedAt: Date } {
  const local = localRecordTime(now, timezone);
  const [h, m] = local.localTime.split(":").map(Number) as [number, number];
  const minutes = h * 60 + m;
  const cat: MealCategory = category ?? (minutes < 630 ? "breakfast" : minutes < 900 ? "lunch" : minutes < 1050 ? "snack" : minutes < 1320 ? "dinner" : "snack");
  const def = category ? DEFAULT_TIME[category] : null;
  if (!def) return { category: cat, consumedAt: now };
  const at = zonedInstant(local.localDate, def, timezone);
  return { category: cat, consumedAt: at.getTime() < now.getTime() ? at : now };
}

async function candidatesFor(userId: string, name: string, prefs: PreferenceLike[]): Promise<DraftCandidate[]> {
  const head = identityTokens(name)[0];
  if (!head) return [];
  const [ref, mine] = await Promise.all([
    referenceService.search(name, 8).catch(() => ({ items: [] as Record<string, unknown>[] })),
    prisma.foodCatalog.findMany({ where: { OR: [{ userId }, { userId: null }], name: { contains: head, mode: "insensitive" } }, orderBy: [{ name: "asc" }, { id: "asc" }], take: 30 }),
  ]);
  const out: (DraftCandidate & { score: number })[] = [];
  const catalogCodes = new Set<string>();
  for (const f of mine) {
    const match = identityMatch(name, f.name);
    if (!match) continue;
    if (f.sourceVersion) catalogCodes.add(f.sourceVersion);
    const per100g = numericNutrients(f) as Record<string, number | null>;
    out.push({
      key: `food:${f.id}`,
      kind: "CATALOG",
      name: f.name,
      source: f.source,
      sourceVersion: f.sourceVersion,
      per100g,
      completeness: completenessOf(per100g),
      match,
      preference: checkFood(f.name, prefs).status,
      score: (match === "EXACT" ? 2 : 1) + (f.userId === userId ? 0.5 : 0.2) + (completenessOf(per100g) === "COMPLETE" ? 0.2 : 0),
    });
  }
  for (const r of ref.items as Record<string, unknown>[]) {
    const rName = String(r.name ?? "");
    const code = String(r.code ?? "");
    const match = identityMatch(name, rName);
    if (!match || !code || catalogCodes.has(code)) continue;
    const raw = (r.per100g ?? {}) as Record<string, unknown>;
    const per100g = Object.fromEntries(NUTRIENTS.map((k) => [k, num(raw[k])]));
    out.push({
      key: `tkpi:${code}`,
      kind: "TKPI",
      name: rName,
      source: String(r.source ?? "Tabel Komposisi Pangan Indonesia"),
      sourceVersion: code,
      per100g,
      completeness: completenessOf(per100g),
      match,
      preference: checkFood(rName, prefs).status,
      score: (match === "EXACT" ? 2 : 1) + (completenessOf(per100g) === "COMPLETE" ? 0.2 : 0) + (rName.length <= name.length + 6 ? 0.1 : 0),
    });
  }
  const seen = new Set<string>();
  return out
    .sort((a, b) => b.score - a.score || a.name.localeCompare(b.name))
    .filter((c) => {
      const k = c.name.toLowerCase();
      if (seen.has(k)) return false;
      seen.add(k);
      return true;
    })
    .slice(0, 3)
    .map(({ score: _score, ...c }) => c);
}

async function portionFor(userId: string, candidate: DraftCandidate | undefined, item: DraftInputItem): Promise<{ grams: number; basis: "user_estimate" } | null> {
  if (!candidate || candidate.kind !== "CATALOG" || !item.unitLabel || item.unit === "g") return null;
  const foodId = candidate.key.slice(5);
  const measure = await prisma.foodPortionMeasure.findFirst({ where: { userId, foodId, label: { equals: item.unitLabel, mode: "insensitive" } } });
  if (!measure) return null;
  return { grams: Math.round(Number(measure.grams) * item.quantity * 10) / 10, basis: "user_estimate" };
}

type DraftRow = NonNullable<Awaited<ReturnType<typeof prisma.mealDraft.findFirst>>>;

export function draftView(d: DraftRow, timezone: string, now = Date.now()) {
  const expired = d.status === "PROPOSED" && d.expiresAt.getTime() < now;
  const local = localRecordTime(d.consumedAt, timezone);
  return {
    id: d.id,
    status: expired ? "EXPIRED" : d.status,
    source: d.source,
    category: d.category,
    consumedAt: d.consumedAt.toISOString(),
    localDate: local.localDate,
    localTime: local.localTime,
    items: d.items as unknown as DraftItem[],
    mealId: d.mealId,
    version: d.version,
    expiresAt: d.expiresAt.toISOString(),
  };
}

async function own(userId: string, id: string) {
  const d = await prisma.mealDraft.findFirst({ where: { id, userId } });
  if (!d) throw notFound("DRAFT_NOT_FOUND", "Draf tidak ditemukan.");
  return d;
}

async function adopt(userId: string, c: DraftCandidate): Promise<string> {
  if (c.kind === "CATALOG") return c.key.slice(5);
  if (c.kind === "WEB") {
    const found = await prisma.foodCatalog.findFirst({ where: { userId, source: c.source, sourceVersion: c.url ?? null }, select: { id: true } });
    if (found) return found.id;
    const per100g = Object.fromEntries(NUTRIENTS.map((k) => [k, c.per100g[k] ?? null]));
    return (await nutritionService.createFood(userId, { name: c.name.slice(0, 120), source: c.source.slice(0, 160), sourceVersion: c.url ?? null, status: "estimated", per100g })).id;
  }
  const existing = await prisma.foodCatalog.findFirst({ where: { userId, source: c.source, sourceVersion: c.sourceVersion }, select: { id: true } });
  if (existing) return existing.id;
  const per100g = Object.fromEntries(NUTRIENTS.map((k) => [k, c.per100g[k] ?? null]));
  const created = await nutritionService.createFood(userId, { name: c.name.slice(0, 120), source: c.source.slice(0, 160), sourceVersion: c.sourceVersion, status: "estimated", per100g });
  return created.id;
}

const WEB_WINDOW_MS = 10 * 60_000;
const WEB_MAX = 10;
const webCalls = new Map<string, number[]>();

const capitalize = (s: string) => (s ? s[0]!.toUpperCase() + s.slice(1) : s);

export const mealDraftService = {
  async webLookup(userId: string, id: string, index: number) {
    await consentService.requireConsent(userId, "health_data_processing");
    const { timezone } = await preferencesService.get(userId);
    const draft = await own(userId, id);
    if (draft.status !== "PROPOSED" || draft.expiresAt.getTime() < Date.now()) throw conflict("DRAFT_NOT_OPEN", "Draf ini sudah tidak bisa diubah.");
    const items = draft.items as unknown as DraftItem[];
    const item = items.find((i) => i.index === index);
    if (!item) throw notFound("DRAFT_ITEM_NOT_FOUND", "Makanan tidak ada di draf ini.");
    if (item.webSearch && item.webSearch.status !== "UNAVAILABLE") return { status: item.webSearch.status, draft: draftView(draft, timezone) };
    if (!webSearchRef.current.configured) return { status: "NOT_CONFIGURED" as const, draft: draftView(draft, timezone) };
    const now = Date.now();
    const recent = (webCalls.get(userId) ?? []).filter((t) => now - t < WEB_WINDOW_MS);
    if (recent.length >= WEB_MAX) {
      webCalls.set(userId, recent);
      throw new AppError(429, "WEB_SEARCH_RATE_LIMITED", "Terlalu sering mencari di web. Coba lagi beberapa menit lagi.");
    }
    webCalls.set(userId, [...recent, now]);

    const run = await prisma.agentRun.create({
      data: { userId, status: "RUNNING", intent: "MEAL_DRAFT_ENRICHMENT", inputText: item.name.slice(0, 200), idempotencyKey: `web-${id}-${index}-${now}`, expiresAt: new Date(now + 3_600_000), state: { draftId: id, index } },
    });
    const ctx: ToolContext = { userId, runId: run.id, intent: "MEAL_DRAFT_ENRICHMENT", maxCalls: 1, callsUsed: 0 };
    let results: WebNutritionResult[] | null = null;
    try {
      results = await executeTool<WebNutritionResult[]>(ctx, "search_web_nutrition", { query: item.name.slice(0, 80) });
    } catch {
      results = null;
    }
    const prefs = await foodPreferencesService.activeFor(userId);
    const found: DraftCandidate[] = [];
    const seen = new Set<string>();
    for (const r of results ?? []) {
      const match = identityMatch(item.name, r.name);
      if (!match || !r.per100g || seen.has(r.host)) continue;
      seen.add(r.host);
      const per100g = r.per100g as unknown as Record<string, number | null>;
      found.push({
        key: `web:${createHash("sha256").update(r.url).digest("hex").slice(0, 16)}`,
        kind: "WEB",
        url: r.url,
        host: r.host,
        name: (r.name || capitalize(item.name)).slice(0, 120),
        source: `Web: ${r.host}`.slice(0, 160),
        sourceVersion: null,
        per100g,
        completeness: completenessOf(per100g),
        match,
        preference: checkFood(item.name, prefs).status,
      });
      if (found.length >= 3) break;
    }
    const status: "FOUND" | "NONE" | "UNAVAILABLE" = results === null ? "UNAVAILABLE" : found.length ? "FOUND" : "NONE";
    const nextItems = items.map((i) => (i.index === index ? { ...i, candidates: [...i.candidates.filter((c) => c.kind !== "WEB"), ...found], webSearch: { status, at: new Date().toISOString() } } : i));
    await prisma.$transaction(async (tx) => {
      await tx.agentRun.update({ where: { id: run.id }, data: { status: results === null ? "FAILED" : "COMPLETED", toolCallsUsed: ctx.callsUsed, version: { increment: 1 }, state: { draftId: id, index, status, results: results?.length ?? 0, usable: found.length } } });
      const moved = await tx.mealDraft.updateMany({ where: { id, userId, status: "PROPOSED", version: draft.version }, data: { items: nextItems as unknown as Prisma.InputJsonArray, version: { increment: 1 } } });
      if (moved.count !== 1) throw conflict("VERSION_CONFLICT", "Draf berubah bersamaan. Muat ulang.");
      await recordAudit(tx, { userId, eventType: "meal_draft_web_lookup", metadata: { draftId: id, index, status, usable: found.length } });
    });
    return { status, draft: draftView(await own(userId, id), timezone) };
  },

  async propose(userId: string, input: { threadId: string | null; source: "TEXT" | "PHOTO"; text: string | null; category: MealCategory | null; items: DraftInputItem[]; now?: Date }) {
    await consentService.requireConsent(userId, "health_data_processing");
    const now = input.now ?? new Date();
    const { timezone } = await preferencesService.get(userId);
    const prefs = await foodPreferencesService.activeFor(userId);
    const when = inferMealTime(input.category, now, timezone);
    const items: DraftItem[] = [];
    for (const [index, it] of input.items.slice(0, 10).entries()) {
      const candidates = await candidatesFor(userId, it.name, prefs);
      const selected = candidates.find((c) => c.preference !== "EXCLUDED") ?? null;
      const portion = it.grams === null ? await portionFor(userId, selected ?? undefined, it) : null;
      items.push({
        index,
        text: it.text.slice(0, 120),
        name: it.name,
        quantity: it.quantity,
        unit: it.unit,
        unitLabel: it.unitLabel,
        quantityStated: it.quantityStated,
        grams: it.grams ?? portion?.grams ?? null,
        gramsBasis: it.unit === "g" ? "weighed" : portion ? portion.basis : null,
        photoConfidence: it.photoConfidence ?? null,
        candidates,
        selected: selected?.key ?? null,
      });
    }
    const draft = await prisma.$transaction(async (tx) => {
      const d = await tx.mealDraft.create({
        data: {
          userId,
          threadId: input.threadId,
          source: input.source,
          category: when.category,
          consumedAt: when.consumedAt,
          inputText: input.text ? input.text.slice(0, 1000) : null,
          items: items as unknown as Prisma.InputJsonArray,
          expiresAt: new Date(now.getTime() + DRAFT_TTL_MS),
        },
      });
      await recordAudit(tx, { userId, eventType: "meal_draft_proposed", metadata: { draftId: d.id, source: input.source, items: items.length } });
      return d;
    });
    return draftView(draft, timezone, now.getTime());
  },

  async get(userId: string, id: string) {
    await consentService.requireConsent(userId, "health_data_processing");
    const { timezone } = await preferencesService.get(userId);
    return draftView(await own(userId, id), timezone);
  },

  async viewsFor(userId: string, ids: string[]) {
    if (ids.length === 0) return new Map<string, ReturnType<typeof draftView>>();
    const { timezone } = await preferencesService.get(userId);
    const rows = await prisma.mealDraft.findMany({ where: { id: { in: ids }, userId } });
    return new Map(rows.map((r) => [r.id, draftView(r, timezone)]));
  },

  async confirm(userId: string, id: string, input: DraftConfirm) {
    await consentService.requireConsent(userId, "health_data_processing");
    const { timezone } = await preferencesService.get(userId);
    const draft = await own(userId, id);
    if (draft.status === "SAVED" && draft.mealId) return { replayed: true, draft: draftView(draft, timezone), mealId: draft.mealId };
    if (draft.status !== "PROPOSED") throw conflict("DRAFT_NOT_OPEN", "Draf ini sudah tidak bisa disimpan.", { status: draft.status });
    if (draft.expiresAt.getTime() < Date.now()) throw conflict("DRAFT_EXPIRED", "Draf sudah kedaluwarsa. Tulis lagi makananmu.");
    if (draft.version !== input.expectedVersion) throw conflict("VERSION_CONFLICT", "Draf berubah. Muat ulang.", { currentVersion: draft.version });
    const known = draft.items as unknown as DraftItem[];
    const used = new Set<number>();
    const mealItems = [];
    for (const it of input.items) {
      const source = known.find((k) => k.index === it.index);
      if (!source || used.has(it.index)) throw unprocessable("INVALID_DRAFT_ITEM", "Item tidak berasal dari draf ini.");
      used.add(it.index);
      const candidate = it.candidateKey === null ? null : source.candidates.find((c) => c.key === it.candidateKey);
      if (it.candidateKey !== null && !candidate) throw unprocessable("INVALID_CANDIDATE", "Pilihan makanan tidak berasal dari draf ini.");
      const foodId = candidate ? await adopt(userId, candidate) : null;
      const grams = it.unit === "g" ? it.quantity : it.grams;
      mealItems.push({
        foodId,
        name: (candidate?.name ?? it.name).slice(0, 120),
        quantity: it.quantity,
        unit: it.unit,
        grams,
        gramsBasis: it.unit === "g" ? null : grams === null ? null : ("user_estimate" as const),
      });
    }
    const parsed = mealCreateSchema.safeParse({ id: draft.id, category: input.category, consumedAt: input.consumedAt, notes: null, items: mealItems });
    if (!parsed.success) throw unprocessable("INVALID_MEAL", "Isi catatan makan tidak valid.", { issues: parsed.error.issues.map((i) => i.path.join(".")) });
    const meal = await nutritionService.create(userId, parsed.data);
    const moved = await prisma.$transaction(async (tx) => {
      const r = await tx.mealDraft.updateMany({ where: { id: draft.id, userId, status: "PROPOSED", version: draft.version }, data: { status: "SAVED", mealId: meal.id, resolvedAt: new Date(), version: { increment: 1 } } });
      if (r.count === 1) await recordAudit(tx, { userId, eventType: "meal_draft_saved", metadata: { draftId: draft.id, mealId: meal.id } });
      return r.count;
    });
    const fresh = await own(userId, id);
    if (moved === 0 && fresh.mealId !== meal.id) throw conflict("VERSION_CONFLICT", "Draf berubah bersamaan. Muat ulang.");
    return { replayed: moved === 0, draft: draftView(fresh, timezone), mealId: meal.id };
  },

  async discard(userId: string, id: string) {
    const { timezone } = await preferencesService.get(userId);
    const draft = await own(userId, id);
    if (draft.status === "DISCARDED") return draftView(draft, timezone);
    if (draft.status !== "PROPOSED") throw conflict("DRAFT_NOT_OPEN", "Draf ini sudah tidak bisa dibuang.", { status: draft.status });
    await prisma.$transaction(async (tx) => {
      await tx.mealDraft.updateMany({ where: { id, userId, status: "PROPOSED" }, data: { status: "DISCARDED", resolvedAt: new Date(), version: { increment: 1 } } });
      await recordAudit(tx, { userId, eventType: "meal_draft_discarded", metadata: { draftId: id } });
    });
    return draftView(await own(userId, id), timezone);
  },
};
