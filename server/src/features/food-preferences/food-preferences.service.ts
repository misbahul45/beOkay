import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { conflict, notFound } from "../../shared/errors/app-error.ts";
import { consentService } from "../consent/consent.service.ts";
import { canonicalTerm, checkFood, RESTRICTION_PRESETS, type PreferenceCheck, type PreferenceKind, type PreferenceLike, type Severity } from "./food-preferences.model.ts";
import type { PreferenceCreate, PreferencePatch } from "./food-preferences.schema.ts";

const requireHealth = (userId: string) => consentService.requireConsent(userId, "health_data_processing");
type Row = NonNullable<Awaited<ReturnType<typeof prisma.foodPreference.findFirst>>>;

const view = (r: Row) => ({
  id: r.id,
  kind: r.kind as PreferenceKind,
  term: r.term,
  label: r.label,
  severity: r.severity as Severity,
  notes: r.notes,
  version: r.version,
  archivedAt: r.archivedAt?.toISOString() ?? null,
  createdAt: r.createdAt.toISOString(),
  updatedAt: r.updatedAt.toISOString(),
});

const severityFor = (kind: PreferenceKind): Severity => (kind === "allergy" || kind === "restriction" ? "strict" : "soft");

export const foodPreferencesService = {
  presets: () => Object.entries(RESTRICTION_PRESETS).map(([term, v]) => ({ term, label: v.label })),

  async list(userId: string, archived = false) {
    await requireHealth(userId);
    const rows = await prisma.foodPreference.findMany({
      where: { userId, archivedAt: archived ? { not: null } : null },
      orderBy: [{ kind: "asc" }, { term: "asc" }],
    });
    return { items: rows.map(view), presets: this.presets() };
  },

  /** Idempoten: istilah sama dengan jenis sama mengembalikan catatan yang ada; yang diarsipkan dipulihkan. */
  async create(userId: string, input: PreferenceCreate) {
    await requireHealth(userId);
    const term = canonicalTerm(input.term);
    if (term.length < 2) throw conflict("INVALID_TERM", "Istilah tidak valid.");
    const label = input.label ?? RESTRICTION_PRESETS[term]?.label ?? input.term.trim();
    const kind = input.kind;
    return prisma.$transaction(async (tx) => {
      const existing = await tx.foodPreference.findUnique({ where: { userId_kind_term: { userId, kind, term } } });
      if (existing && !existing.archivedAt) return { created: false, item: view(existing) };
      if (existing) {
        const restored = await tx.foodPreference.update({
          where: { id: existing.id },
          data: { archivedAt: null, label, notes: input.notes ?? null, version: { increment: 1 } },
        });
        await recordAudit(tx, { userId, eventType: "food_preference_restored", metadata: { recordId: restored.id, kind } });
        return { created: true, item: view(restored) };
      }
      try {
        const saved = await tx.foodPreference.create({ data: { userId, kind, term, label, severity: severityFor(kind), notes: input.notes ?? null } });
        await recordAudit(tx, { userId, eventType: "food_preference_created", metadata: { recordId: saved.id, kind } });
        return { created: true, item: view(saved) };
      } catch (e) {
        if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") throw conflict("PREFERENCE_EXISTS", "Preferensi ini sudah ada.");
        throw e;
      }
    });
  },

  async update(userId: string, id: string, input: PreferencePatch) {
    await requireHealth(userId);
    return prisma.$transaction(async (tx) => {
      const row = await tx.foodPreference.findFirst({ where: { id, userId } });
      if (!row) throw notFound("PREFERENCE_NOT_FOUND", "Preferensi tidak ditemukan.");
      if (row.version !== input.expectedVersion) throw conflict("VERSION_CONFLICT", "Preferensi sudah berubah. Muat ulang lalu coba lagi.", { currentVersion: row.version });
      const saved = await tx.foodPreference.update({
        where: { id },
        data: {
          ...(input.label !== undefined ? { label: input.label } : {}),
          ...(input.notes !== undefined ? { notes: input.notes } : {}),
          ...(input.archived !== undefined ? { archivedAt: input.archived ? new Date() : null } : {}),
          version: { increment: 1 },
        },
      });
      await recordAudit(tx, { userId, eventType: "food_preference_updated", metadata: { recordId: id, archived: input.archived ?? null } });
      return view(saved);
    });
  },

  /** Preferensi aktif milik pengguna sebagai masukan pencocokan (tanpa memeriksa consent: dipakai layanan yang sudah memeriksanya). */
  async activeFor(userId: string): Promise<PreferenceLike[]> {
    const rows = await prisma.foodPreference.findMany({ where: { userId, archivedAt: null } });
    return rows.map((r) => ({ id: r.id, kind: r.kind as PreferenceKind, term: r.term, label: r.label, severity: r.severity as Severity }));
  },

  async check(userId: string, items: { name: string; brand?: string | null }[]): Promise<{ hasStrictConstraints: boolean; results: (PreferenceCheck & { name: string })[] }> {
    await requireHealth(userId);
    const prefs = await this.activeFor(userId);
    return {
      hasStrictConstraints: prefs.some((p) => p.severity === "strict"),
      results: items.map((i) => ({ name: i.name, ...checkFood(i.name, prefs, i.brand) })),
    };
  },
};
