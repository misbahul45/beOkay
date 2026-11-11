import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { outbox, type OutboxHandlers } from "../../infrastructure/queue/outbox.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { consentService } from "../consent/consent.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { personalization, tokensOf } from "./personalization.ts";

/**
 * Lingkar tertutup: rencana yang DITERIMA dicocokkan dengan catatan nyata pengguna (catatan makan, sesi aktivitas).
 * Hasil ini TERUKUR dan berbeda dari umpan balik yang dilaporkan sendiri. Aturan pencocokan sengaja sederhana dan dapat dijelaskan:
 *  - makanan: butir catatan makan sesudah rencana diterima dengan food_id/kode sumber sama, ATAU nama memuat kata bermakna yang sama
 *    (semua kata bila nama rencana ≤ 2 kata, selainnya minimal dua kata);
 *  - aktivitas: sesi pada tanggal rencana (zona waktu pengguna), jenis sama, durasi ≥ 50% dari rencana.
 * Bila catatan pembuktinya kemudian diarsipkan, hasil ditarik dan pengaruhnya pada personalisasi dibatalkan.
 */
export const OUTCOME_WINDOW_DAYS = 14;
export const MIN_ACTIVITY_FRACTION = 0.5;

export function nameMatches(planned: string, logged: string): boolean {
  const need = tokensOf(planned);
  if (need.length === 0) return false;
  const have = new Set(tokensOf(logged));
  const hit = need.filter((t) => have.has(t)).length;
  return need.length <= 2 ? hit === need.length : hit >= 2;
}

async function allowed(userId: string) {
  try {
    await consentService.requireConsent(userId, "health_data_processing");
    await consentService.requireConsent(userId, "personalized_ai");
    return true;
  } catch {
    return false;
  }
}

export const outcomes = {
  async reconcile(userId: string): Promise<{ observed: number; retracted: number }> {
    if (!(await allowed(userId))) return { observed: 0, retracted: 0 };
    const since = new Date(Date.now() - OUTCOME_WINDOW_DAYS * 86_400_000);
    let observed = 0, retracted = 0;

    // 1. Tarik hasil yang buktinya sudah diarsipkan atau dihapus.
    for (const o of await prisma.recommendationOutcome.findMany({ where: { userId }, include: { recommendation: true } })) {
      const alive = o.evidenceType === "meal_item"
        ? await prisma.mealItem.findFirst({ where: { id: o.evidenceId, meal: { userId, archivedAt: null } }, select: { id: true } })
        : await prisma.activitySession.findFirst({ where: { id: o.evidenceId, userId, archivedAt: null }, select: { id: true } });
      if (alive) continue;
      const planned = await prisma.plannedMeal.findUnique({ where: { recommendationId: o.recommendationId } });
      try {
        await prisma.$transaction(async (tx) => {
          const gone = await tx.recommendationOutcome.deleteMany({ where: { id: o.id } });
          if (gone.count !== 1) return;
          await outbox.enqueue(tx, { userId, type: "outcome.retracted", payload: { recommendationId: o.recommendationId, kind: o.kind, foodName: planned?.name ?? null }, dedupeKey: `outcome-retracted:${o.id}` });
          retracted++;
        });
      } catch (e) {
        if (!(e instanceof Prisma.PrismaClientKnownRequestError)) throw e;
      }
    }

    // 2. Rencana makan yang belum punya hasil.
    const plans = await prisma.plannedMeal.findMany({ where: { userId, createdAt: { gte: since }, recommendation: { outcome: null } }, take: 50 });
    for (const plan of plans) {
      const items = await prisma.mealItem.findMany({ where: { meal: { userId, archivedAt: null, consumedAt: { gte: plan.createdAt, lte: new Date() } } }, include: { meal: { select: { consumedAt: true } } }, orderBy: { meal: { consumedAt: "asc" } }, take: 200 });
      const hit = items.find((i) => (plan.sourceRef && (i.foodId === plan.sourceRef)) || nameMatches(plan.name, i.name));
      if (!hit) continue;
      if (await record(userId, plan.recommendationId, "MEAL_LOGGED", "meal_item", hit.id, hit.meal.consumedAt, plan.name)) observed++;
    }

    // 3. Rencana aktivitas.
    const tz = (await preferencesService.get(userId)).timezone;
    const aplans = await prisma.activityPlan.findMany({ where: { userId, createdAt: { gte: since }, recommendation: { outcome: null } }, take: 50 });
    for (const plan of aplans) {
      const day = plan.plannedFor.toISOString().slice(0, 10);
      const lo = new Date(plan.plannedFor.getTime() - 86_400_000), hi = new Date(plan.plannedFor.getTime() + 2 * 86_400_000);
      const sessions = await prisma.activitySession.findMany({ where: { userId, archivedAt: null, activityType: plan.activityType, startedAt: { gte: lo, lt: hi } }, orderBy: { startedAt: "asc" }, take: 20 });
      const hit = sessions.find((s) => localRecordTime(s.startedAt, tz).localDate === day && s.durationMinutes >= plan.durationMinutes * MIN_ACTIVITY_FRACTION);
      if (!hit) continue;
      if (await record(userId, plan.recommendationId, "ACTIVITY_LOGGED", "activity_session", hit.id, hit.startedAt, null)) observed++;
    }
    return { observed, retracted };
  },

  /** Penangan outbox. Idempoten karena pengaruh pada personalisasi hanya diterapkan sekali per (rekomendasi, arah). */
  handlers: ((): OutboxHandlers => {
    const applyOnce = async (ev: { userId: string | null; payload: Record<string, unknown> }, direction: 1 | -1) => {
      const name = ev.payload.foodName as string | null;
      if (!ev.userId || !name) return;
      await personalization.applyOutcome(ev.userId, String(ev.payload.recommendationId), name, direction);
    };
    return {
      "outcome.observed": (ev) => applyOnce(ev, 1),
      "outcome.retracted": (ev) => applyOnce(ev, -1),
      "recommendation.decided": async () => {},
      "recommendation.feedback": async () => {},
      "intervention.responded": async () => {},
      "coaching.decided": async () => {},
      "coaching.feedback": async () => {},
      "coaching.checkin": async () => {},
    };
  })(),
};

async function record(userId: string, recommendationId: string, kind: "MEAL_LOGGED" | "ACTIVITY_LOGGED", evidenceType: "meal_item" | "activity_session", evidenceId: string, observedAt: Date, foodName: string | null): Promise<boolean> {
  try {
    await prisma.$transaction(async (tx) => {
      const o = await tx.recommendationOutcome.create({ data: { userId, recommendationId, kind, evidenceType, evidenceId, observedAt } });
      await outbox.enqueue(tx, { userId, type: "outcome.observed", payload: { recommendationId, kind, foodName }, dedupeKey: `outcome-observed:${o.id}` });
    });
    return true;
  } catch (e) {
    if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") return false; // dua rekonsiliasi bersamaan: yang kedua mengalah
    throw e;
  }
}
