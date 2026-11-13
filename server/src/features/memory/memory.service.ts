import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { conflict, forbidden, notFound } from "../../shared/errors/app-error.ts";
import { consentService } from "../consent/consent.service.ts";
import { ACTIVITY_COUNTED_QUALITY } from "../activity/activity.model.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { emitDomainEvent } from "../../infrastructure/queue/events.ts";
import { MEMORY_KIND_LABELS, extractMemoryCandidates, ttlDaysFor, type MemoryCandidate, type MemoryKind } from "./memory.extract.ts";

const DAY = 86_400_000;
const notExpired = () => ({ OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }] });
const expiryFor = (kind: string, key: string, from = new Date()) => {
  const ttl = ttlDaysFor(kind, key);
  return ttl ? new Date(from.getTime() + ttl * DAY) : null;
};

type Row = NonNullable<Awaited<ReturnType<typeof prisma.memoryItem.findFirst>>>;
type Tx = Prisma.TransactionClient;

export const MEMORY_TYPE_OF: Record<string, string> = {
  ACTIVITY_TIME: "ROUTINE",
  SCHEDULE: "ROUTINE",
  AVAILABLE_MINUTES: "ROUTINE",
  ACTIVITY_LIKE: "PREFERENCE",
  ACTIVITY_DISLIKE: "PREFERENCE",
  FOOD_CONTEXT: "PREFERENCE",
  BARRIER: "BARRIER",
  HEALTH_EVENT: "EPISODE",
};

export const SKILL_MEMORY_KINDS: Record<string, readonly string[]> = {
  "nutrition.coach": ["FOOD_CONTEXT", "HEALTH_EVENT", "BARRIER"],
  "activity.planner": ["ACTIVITY_TIME", "SCHEDULE", "AVAILABLE_MINUTES", "ACTIVITY_LIKE", "ACTIVITY_DISLIKE", "HEALTH_EVENT", "BARRIER"],
  "behavior.barrier_solver": ["BARRIER", "SCHEDULE", "AVAILABLE_MINUTES", "HEALTH_EVENT"],
  "memory.reflector": ["ACTIVITY_TIME", "SCHEDULE", "AVAILABLE_MINUTES", "ACTIVITY_LIKE", "ACTIVITY_DISLIKE", "FOOD_CONTEXT", "BARRIER", "HEALTH_EVENT"],
};

export const DEFAULT_MEMORY_BUDGET = 5;
export const DERIVED_MIN_SESSIONS = 4;
export const DERIVED_MIN_SHARE = 0.6;
export const DERIVED_WINDOW_DAYS = 28;

export const dayPartOfHour = (h: number): "pagi" | "siang" | "sore" | "malam" | null => (h >= 4 && h < 11 ? "pagi" : h >= 11 && h < 15 ? "siang" : h >= 15 && h < 18 ? "sore" : h >= 18 && h < 22 ? "malam" : null);

export function derivedActivityTime(hours: number[]): { part: "pagi" | "siang" | "sore" | "malam"; count: number; total: number } | null {
  const parts = hours.map(dayPartOfHour).filter((p): p is NonNullable<typeof p> => p !== null);
  if (parts.length < DERIVED_MIN_SESSIONS) return null;
  const counts = new Map<string, number>();
  for (const p of parts) counts.set(p, (counts.get(p) ?? 0) + 1);
  const [part, count] = [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0]!;
  return count / parts.length >= DERIVED_MIN_SHARE ? { part: part as "pagi", count, total: parts.length } : null;
}

async function revise(tx: Tx | typeof prisma, m: Row, change: string, reason?: string | null) {
  await tx.memoryRevision.createMany({ data: [{ memoryId: m.id, userId: m.userId, version: m.version, content: m.content, status: m.status, change, reason: reason ?? null }], skipDuplicates: true });
}

async function changed(tx: Tx | typeof prisma, m: Row, change: string) {
  await emitDomainEvent(tx, { userId: m.userId, type: "memory.changed", dedupeKey: `memory:${m.id}:v${m.version}:${change}:${Date.now()}`, payload: { memoryId: m.id, kind: m.kind, change }, consentScope: "personalized_ai" });
}

export const memoryView = (m: Row) => ({
  id: m.id,
  category: m.category,
  kind: m.kind,
  kindLabel: MEMORY_KIND_LABELS[m.kind as MemoryKind] ?? m.kind,
  content: m.content,
  status: m.status,
  sourceType: m.sourceType,
  version: m.version,
  confirmedAt: m.confirmedAt?.toISOString() ?? null,
  expiresAt: m.expiresAt?.toISOString() ?? null,
  updatedAt: m.updatedAt.toISOString(),
  memoryType: m.memoryType,
  confidence: m.confidence,
  sourceIds: m.sourceIds,
  validFrom: m.validFrom?.toISOString() ?? null,
  lastVerifiedAt: m.lastVerifiedAt?.toISOString() ?? null,
  privacyScope: m.privacyScope,
  conflictState: m.conflictState,
  supersededBy: m.supersededBy,
  paused: m.pausedAt !== null,
  pausedAt: m.pausedAt?.toISOString() ?? null,
  pauseReason: m.pauseReason,
});

async function enabledSetting(userId: string) {
  const s = await prisma.userSettings.findUnique({ where: { userId }, select: { memoryEnabled: true } });
  return s?.memoryEnabled ?? true;
}

async function consentGiven(userId: string) {
  try {
    await consentService.requireConsent(userId, "personalized_ai");
    return true;
  } catch {
    return false;
  }
}

async function own(userId: string, id: string) {
  const m = await prisma.memoryItem.findFirst({ where: { id, userId } });
  if (!m) throw notFound("MEMORY_NOT_FOUND", "Ingatan tidak ditemukan.");
  return m;
}

export const memoryService = {
  async allowed(userId: string) {
    return (await enabledSetting(userId)) && (await consentGiven(userId));
  },

  async propose(userId: string, text: string, sourceId: string | null, extra: MemoryCandidate[] = [], source: "CONVERSATION" | "LANGUAGE_MODEL" = "CONVERSATION") {
    if (!(await this.allowed(userId))) return [];
    const created: Row[] = [];
    const found = extractMemoryCandidates(text);
    const candidates = [...found, ...extra.filter((e) => !found.some((f) => f.kind === e.kind))];
    for (const c of candidates) {
      const fromModel = source === "LANGUAGE_MODEL" && extra.includes(c);
      const [active, dismissed, pending] = await Promise.all([
        prisma.memoryItem.findFirst({ where: { userId, key: c.key, status: "ACTIVE" } }),
        prisma.memoryItem.findFirst({ where: { userId, key: c.key, status: "DISMISSED", content: c.content } }),
        prisma.memoryItem.findFirst({ where: { userId, key: c.key, status: "PROPOSED" } }),
      ]);
      if (active?.content === c.content || dismissed) continue;
      if (pending) {
        if (pending.content === c.content) {
          created.push(pending);
          continue;
        }
        await prisma.memoryItem.delete({ where: { id: pending.id } });
      }
      const conflicting = Boolean(active && active.content !== c.content);
      try {
        const row = await prisma.memoryItem.create({
            data: {
              memoryType: MEMORY_TYPE_OF[c.kind] ?? "FACT",
              sourceIds: sourceId ? [sourceId] : [],
              conflictState: conflicting ? "CONFLICTING" : "NONE",
              userId,
              category: "PREFERENCE",
              kind: c.kind,
              key: c.key,
              content: c.content,
              status: "PROPOSED",
              sourceType: fromModel ? "LANGUAGE_MODEL" : "CONVERSATION",
              confidence: fromModel ? "INFERRED" : "STATED",
              sensitivity: c.kind === "HEALTH_EVENT" ? "MEDIUM" : "LOW",
              retention: expiryFor(c.kind, c.key) ? "EXPIRES" : "UNTIL_DELETED",
              expiresAt: expiryFor(c.kind, c.key),
              sourceId,
            },
          });
        await revise(prisma, row, "PROPOSED");
        if (conflicting) {
          await prisma.memoryItem.update({ where: { id: active!.id }, data: { conflictState: "CONFLICTING" } });
          await revise(prisma, row, "CONFLICT", `Bertentangan dengan ingatan tersimpan ${active!.id}`);
        }
        created.push(row);
      } catch (e) {
        if (!(e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002")) throw e;
      }
    }
    return created;
  },

  async activeFor(userId: string) {
    if (!(await this.allowed(userId))) return [];
    return prisma.memoryItem.findMany({ where: { userId, status: "ACTIVE", pausedAt: null, privacyScope: { not: "SOCIAL" }, ...notExpired() }, orderBy: [{ updatedAt: "desc" }, { id: "asc" }], take: 50 });
  },

  async proposeDerived(userId: string, now = new Date()) {
    if (!(await this.allowed(userId))) return null;
    const existing = await prisma.memoryItem.findFirst({ where: { userId, key: "ACTIVITY_TIME", status: { in: ["ACTIVE", "PROPOSED"] } } });
    if (existing) return null;
    const { timezone } = await preferencesService.get(userId);
    const sessions = await prisma.activitySession.findMany({ where: { userId, archivedAt: null, qualityStatus: { in: [...ACTIVITY_COUNTED_QUALITY] }, startedAt: { gte: new Date(now.getTime() - DERIVED_WINDOW_DAYS * DAY) } }, select: { id: true, startedAt: true }, orderBy: { startedAt: "desc" }, take: 60 });
    const hourOf = (d: Date) => Number(new Intl.DateTimeFormat("en-GB", { timeZone: timezone, hour: "2-digit", hour12: false }).format(d)) % 24;
    const found = derivedActivityTime(sessions.map((x) => hourOf(x.startedAt)));
    if (!found) return null;
    const content = `Lebih suka beraktivitas ${found.part} hari`;
    if (await prisma.memoryItem.findFirst({ where: { userId, key: "ACTIVITY_TIME", status: "DISMISSED", content } })) return null;
    const ids = sessions.filter((x) => dayPartOfHour(hourOf(x.startedAt)) === found.part).map((x) => x.id).slice(0, 20);
    try {
      const row = await prisma.memoryItem.create({ data: { userId, category: "PREFERENCE", kind: "ACTIVITY_TIME", key: "ACTIVITY_TIME", content, status: "PROPOSED", sourceType: "DERIVED", memoryType: "DERIVED", confidence: "INFERRED", sourceIds: ids, sourceId: null, retention: "UNTIL_DELETED" } });
      await revise(prisma, row, "PROPOSED", `Dari catatanmu: ${found.count} dari ${found.total} sesi`);
      return row;
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") return null;
      throw e;
    }
  },

  async retrieve(userId: string, skillId: string, budget = DEFAULT_MEMORY_BUDGET) {
    const kinds = SKILL_MEMORY_KINDS[skillId];
    if (!kinds || !(await this.allowed(userId))) return { items: [] as Row[], ids: [] as string[], budget, skillId, withheld: kinds ? "MEMORY_NOT_ALLOWED" : "SKILL_HAS_NO_MEMORY_ACCESS" };
    const social = await consentService.hasConsent(userId, "social_outcomes_memory");
    const rows = await prisma.memoryItem.findMany({
      where: { userId, status: "ACTIVE", pausedAt: null, kind: { in: [...kinds] }, ...(social ? {} : { privacyScope: { not: "SOCIAL" } }), ...notExpired() },
      orderBy: [{ confirmedAt: { sort: "desc", nulls: "last" } }, { updatedAt: "desc" }, { id: "asc" }],
      take: Math.max(0, Math.min(budget, 10)),
    });
    return { items: rows, ids: rows.map((r) => r.id), budget, skillId, withheld: null };
  },

  async pause(userId: string, id: string, reason = "USER") {
    const row = await own(userId, id);
    if (row.status !== "ACTIVE") throw conflict("MEMORY_NOT_ACTIVE", "Hanya ingatan yang tersimpan yang bisa dijeda.");
    if (row.pausedAt) return memoryView(row);
    const saved = await prisma.$transaction(async (tx) => {
      const r = await tx.memoryItem.update({ where: { id }, data: { pausedAt: new Date(), pauseReason: reason, version: { increment: 1 } } });
      await revise(tx, r, "PAUSED", reason);
      await changed(tx, r, "PAUSED");
      await recordAudit(tx, { userId, eventType: "memory_paused", metadata: { memoryId: id } });
      return r;
    });
    return memoryView(saved);
  },

  async resume(userId: string, id: string) {
    if (!(await this.allowed(userId))) throw forbidden("MEMORY_DISABLED", "Ingatan sedang tidak aktif atau persetujuan saran personal belum diberikan.");
    const row = await own(userId, id);
    if (!row.pausedAt) return memoryView(row);
    const saved = await prisma.$transaction(async (tx) => {
      const r = await tx.memoryItem.update({ where: { id }, data: { pausedAt: null, pauseReason: null, lastVerifiedAt: new Date(), version: { increment: 1 } } });
      await revise(tx, r, "RESUMED");
      await changed(tx, r, "RESUMED");
      await recordAudit(tx, { userId, eventType: "memory_resumed", metadata: { memoryId: id } });
      return r;
    });
    return memoryView(saved);
  },

  async history(userId: string, id: string) {
    await own(userId, id);
    const rows = await prisma.memoryRevision.findMany({ where: { userId, memoryId: id }, orderBy: [{ createdAt: "asc" }, { version: "asc" }] });
    return { items: rows.map((r) => ({ version: r.version, change: r.change, content: r.content, status: r.status, reason: r.reason, at: r.createdAt.toISOString() })) };
  },

  async viewsFor(userId: string, ids: string[]) {
    if (ids.length === 0) return new Map<string, ReturnType<typeof memoryView>>();
    const rows = await prisma.memoryItem.findMany({ where: { id: { in: ids }, userId } });
    return new Map(rows.map((r) => [r.id, memoryView(r)]));
  },

  async list(userId: string) {
    const [enabled, consent, rows] = await Promise.all([
      enabledSetting(userId),
      consentGiven(userId),
      prisma.memoryItem.findMany({ where: { userId, status: { in: ["ACTIVE", "PROPOSED"] }, ...notExpired() }, orderBy: [{ updatedAt: "desc" }, { id: "asc" }] }),
    ]);
    const active = rows.filter((r) => r.status === "ACTIVE");
    return {
      enabled,
      consentGiven: consent,
      active: enabled && consent,
      items: active.filter((r) => !r.pausedAt).map(memoryView),
      paused: active.filter((r) => r.pausedAt).map(memoryView),
      conflicts: rows.filter((r) => r.status === "PROPOSED" && r.conflictState === "CONFLICTING").map(memoryView),
      proposals: rows.filter((r) => r.status === "PROPOSED" && r.conflictState !== "CONFLICTING" && r.sourceType === "DERIVED").map(memoryView),
    };
  },

  async confirm(userId: string, id: string) {
    if (!(await this.allowed(userId))) throw forbidden("MEMORY_DISABLED", "Ingatan sedang tidak aktif atau persetujuan saran personal belum diberikan.");
    const row = await own(userId, id);
    if (row.status === "ACTIVE") return memoryView(row);
    if (row.status !== "PROPOSED") throw conflict("MEMORY_NOT_PROPOSED", "Usulan ini sudah tidak berlaku.");
    const saved = await prisma.$transaction(async (tx) => {
      const active = await tx.memoryItem.findFirst({ where: { userId, key: row.key, status: "ACTIVE" } });
      let result: Row;
      const now = new Date();
      if (active) {
        await revise(tx, active, "SUPERSEDED", "Diganti oleh usulan yang kamu konfirmasi");
        result = await tx.memoryItem.update({ where: { id: active.id }, data: { content: row.content, sourceId: row.sourceId, sourceIds: [...new Set([...active.sourceIds, ...row.sourceIds])], version: { increment: 1 }, confirmedAt: now, lastVerifiedAt: now, validFrom: now, conflictState: "NONE", expiresAt: expiryFor(row.kind, row.key), retention: expiryFor(row.kind, row.key) ? "EXPIRES" : "UNTIL_DELETED" } });
        await tx.memoryItem.delete({ where: { id: row.id } });
      } else {
        result = await tx.memoryItem.update({ where: { id: row.id }, data: { status: "ACTIVE", confirmedAt: now, lastVerifiedAt: now, validFrom: now, conflictState: "NONE", expiresAt: expiryFor(row.kind, row.key) } });
      }
      await revise(tx, result, "CONFIRMED");
      await changed(tx, result, "CONFIRMED");
      await recordAudit(tx, { userId, eventType: "memory_confirmed", metadata: { memoryId: result.id, kind: result.kind } });
      return result;
    });
    return memoryView(saved);
  },

  async dismiss(userId: string, id: string) {
    const row = await own(userId, id);
    if (row.status !== "PROPOSED") return memoryView(row);
    const saved = await prisma.memoryItem.update({ where: { id }, data: { status: "DISMISSED", conflictState: "NONE" } });
    await revise(prisma, saved, "DISMISSED");
    if (row.conflictState === "CONFLICTING") await prisma.memoryItem.updateMany({ where: { userId, key: row.key, status: "ACTIVE", conflictState: "CONFLICTING" }, data: { conflictState: "NONE" } });
    return memoryView(saved);
  },

  async update(userId: string, id: string, input: { content: string; expectedVersion: number }) {
    const row = await own(userId, id);
    if (row.status !== "ACTIVE") throw conflict("MEMORY_NOT_ACTIVE", "Hanya ingatan yang tersimpan yang bisa diubah.");
    const moved = await prisma.$transaction(async (tx) => {
      const r = await tx.memoryItem.updateMany({ where: { id, userId, status: "ACTIVE", version: input.expectedVersion }, data: { content: input.content, sourceType: "USER", version: { increment: 1 } } });
      if (r.count === 1) {
        await recordAudit(tx, { userId, eventType: "memory_updated", metadata: { memoryId: id } });
        const after = (await tx.memoryItem.findFirst({ where: { id, userId } }))!;
        await revise(tx, after, "CORRECTED", "Dikoreksi pengguna");
        await changed(tx, after, "CORRECTED");
      }
      return r.count;
    });
    if (moved !== 1) throw conflict("VERSION_CONFLICT", "Ingatan berubah. Muat ulang.", { currentVersion: row.version });
    return memoryView(await own(userId, id));
  },

  async remove(userId: string, id: string) {
    const row = await own(userId, id);
    await prisma.$transaction(async (tx) => {
      await tx.memoryItem.delete({ where: { id: row.id } });
      await changed(tx, row, "DELETED");
      await recordAudit(tx, { userId, eventType: "memory_deleted", metadata: { kind: row.kind } });
    });
    return { deleted: true, id };
  },

  async removeAll(userId: string) {
    const count = await prisma.$transaction(async (tx) => {
      const r = await tx.memoryItem.deleteMany({ where: { userId } });
      await recordAudit(tx, { userId, eventType: "memory_deleted_all", metadata: { count: r.count } });
      return r.count;
    });
    return { deleted: count };
  },

  async setEnabled(userId: string, enabled: boolean) {
    await prisma.$transaction(async (tx) => {
      await tx.userSettings.upsert({ where: { userId }, update: { memoryEnabled: enabled }, create: { userId, memoryEnabled: enabled } });
      if (!enabled) await tx.memoryItem.deleteMany({ where: { userId, status: "PROPOSED" } });
      await recordAudit(tx, { userId, eventType: "memory_preference_changed", metadata: { enabled } });
    });
    return this.list(userId);
  },
};
