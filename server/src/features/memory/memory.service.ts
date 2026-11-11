import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { conflict, forbidden, notFound } from "../../shared/errors/app-error.ts";
import { consentService } from "../consent/consent.service.ts";
import { MEMORY_KIND_LABELS, extractMemoryCandidates, type MemoryKind } from "./memory.extract.ts";

type Row = NonNullable<Awaited<ReturnType<typeof prisma.memoryItem.findFirst>>>;

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
  updatedAt: m.updatedAt.toISOString(),
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

  async propose(userId: string, text: string, sourceId: string | null) {
    if (!(await this.allowed(userId))) return [];
    const created: Row[] = [];
    for (const c of extractMemoryCandidates(text)) {
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
      try {
        created.push(
          await prisma.memoryItem.create({
            data: { userId, category: "PREFERENCE", kind: c.kind, key: c.key, content: c.content, status: "PROPOSED", sourceType: "CONVERSATION", sourceId },
          }),
        );
      } catch (e) {
        if (!(e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002")) throw e;
      }
    }
    return created;
  },

  async activeFor(userId: string) {
    if (!(await this.allowed(userId))) return [];
    return prisma.memoryItem.findMany({ where: { userId, status: "ACTIVE" }, orderBy: [{ updatedAt: "desc" }, { id: "asc" }], take: 50 });
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
      prisma.memoryItem.findMany({ where: { userId, status: "ACTIVE" }, orderBy: [{ updatedAt: "desc" }, { id: "asc" }] }),
    ]);
    return { enabled, consentGiven: consent, active: enabled && consent, items: rows.map(memoryView) };
  },

  async confirm(userId: string, id: string) {
    if (!(await this.allowed(userId))) throw forbidden("MEMORY_DISABLED", "Ingatan sedang tidak aktif atau persetujuan saran personal belum diberikan.");
    const row = await own(userId, id);
    if (row.status === "ACTIVE") return memoryView(row);
    if (row.status !== "PROPOSED") throw conflict("MEMORY_NOT_PROPOSED", "Usulan ini sudah tidak berlaku.");
    const saved = await prisma.$transaction(async (tx) => {
      const active = await tx.memoryItem.findFirst({ where: { userId, key: row.key, status: "ACTIVE" } });
      let result: Row;
      if (active) {
        result = await tx.memoryItem.update({ where: { id: active.id }, data: { content: row.content, sourceId: row.sourceId, version: { increment: 1 }, confirmedAt: new Date() } });
        await tx.memoryItem.delete({ where: { id: row.id } });
      } else {
        result = await tx.memoryItem.update({ where: { id: row.id }, data: { status: "ACTIVE", confirmedAt: new Date() } });
      }
      await recordAudit(tx, { userId, eventType: "memory_confirmed", metadata: { memoryId: result.id, kind: result.kind } });
      return result;
    });
    return memoryView(saved);
  },

  async dismiss(userId: string, id: string) {
    const row = await own(userId, id);
    if (row.status !== "PROPOSED") return memoryView(row);
    const saved = await prisma.memoryItem.update({ where: { id }, data: { status: "DISMISSED" } });
    return memoryView(saved);
  },

  async update(userId: string, id: string, input: { content: string; expectedVersion: number }) {
    const row = await own(userId, id);
    if (row.status !== "ACTIVE") throw conflict("MEMORY_NOT_ACTIVE", "Hanya ingatan yang tersimpan yang bisa diubah.");
    const moved = await prisma.$transaction(async (tx) => {
      const r = await tx.memoryItem.updateMany({ where: { id, userId, status: "ACTIVE", version: input.expectedVersion }, data: { content: input.content, sourceType: "USER", version: { increment: 1 } } });
      if (r.count === 1) await recordAudit(tx, { userId, eventType: "memory_updated", metadata: { memoryId: id } });
      return r.count;
    });
    if (moved !== 1) throw conflict("VERSION_CONFLICT", "Ingatan berubah. Muat ulang.", { currentVersion: row.version });
    return memoryView(await own(userId, id));
  },

  async remove(userId: string, id: string) {
    const row = await own(userId, id);
    await prisma.$transaction(async (tx) => {
      await tx.memoryItem.delete({ where: { id: row.id } });
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
