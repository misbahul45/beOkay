import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { outbox } from "../../infrastructure/queue/outbox.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { conflict, forbidden, notFound, unprocessable } from "../../shared/errors/app-error.ts";
import { consentService } from "../consent/consent.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { coachingService } from "../coaching/coaching.service.ts";
import { CLARIFICATION_CONTENT, EXPIRY_MS, INTERVENTION_POLICY_VERSION, REPEAT_SUPPRESS_DAYS, USER_INITIATED, classify, contentFor, decide, type Trigger } from "./intervention.policy.ts";
import type { EvaluateInput, PreferencesInput, ResponseInput } from "./intervention.schema.ts";

const COUNTED = ["ELIGIBLE", "DELIVERED", "OPENED", "SNOOZED", "RESPONDED", "EXPIRED"]; // dikirim ke pengguna (bukan dibatalkan)
const OPEN = ["ELIGIBLE", "DELIVERED", "OPENED", "SNOOZED"];

async function consentOk(userId: string) {
  try {
    await consentService.requireConsent(userId, "health_data_processing");
    await consentService.requireConsent(userId, "personalized_ai");
    return true;
  } catch {
    return false;
  }
}

export function localClock(now: Date, tz: string) {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(now);
  const p = (t: string) => parts.find((x) => x.type === t)!.value;
  return { localDate: `${p("year")}-${p("month")}-${p("day")}`, minute: Number(p("hour")) * 60 + Number(p("minute")) };
}

const DEFAULTS = { pausedUntil: null as Date | null, quietStartMinute: 1320, quietEndMinute: 420, maxPerDay: 2, maxPerWeek: 7, mutedTriggers: [] as string[] };
async function prefsOf(userId: string) {
  return (await prisma.interventionPreference.findUnique({ where: { userId } })) ?? { userId, ...DEFAULTS };
}

type Row = NonNullable<Awaited<ReturnType<typeof prisma.interventionDecision.findFirst>>>;
const view = (r: Row, replayed = false) => ({
  id: r.id,
  trigger: r.triggerType,
  option: r.option,
  decision: classify({ option: r.option as Parameters<typeof classify>[0]["option"], reason: r.reason }),
  reason: r.reason,
  deliveryStatus: r.deliveryStatus,
  content: r.content,
  expiresAt: r.expiresAt?.toISOString() ?? null,
  snoozedUntil: r.snoozedUntil?.toISOString() ?? null,
  response: r.response,
  policyVersion: r.policyVersion,
  decidedAt: r.decidedAt.toISOString(),
  replayed,
});

export const interventionService = {
  /** Satu titik keputusan. Selalu mencatat hasilnya, termasuk "tidak mengintervensi" beserta alasannya. */
  async evaluate(userId: string, input: EvaluateInput, now = new Date()) {
    const trigger = input.trigger as Trigger;
    const consent = await consentOk(userId);
    const tz = (await preferencesService.get(userId)).timezone;
    const clock = localClock(now, tz);
    const prefs = await prefsOf(userId);

    let goal: { id: string; title: string } | null = null;
    const needsGoal = trigger === "GOAL_WINDOW_APPROACHING" || trigger === "USER_SELECTED_ROUTINE_REMINDER";
    if (consent && needsGoal) {
      goal = input.goalId
        ? await prisma.behaviorGoal.findFirst({ where: { id: input.goalId, userId, status: "active" }, select: { id: true, title: true } })
        : await prisma.behaviorGoal.findFirst({ where: { userId, status: "active" }, orderBy: { createdAt: "desc" }, select: { id: true, title: true } });
      if (input.goalId && !goal) throw notFound("GOAL_NOT_FOUND", "Tujuan tidak ditemukan.");
    }
    const due = consent && trigger === "COACHING_ACTION_DUE" ? await coachingService.dueToday(userId, now) : null;
    const reviewDone = consent && trigger === "WEEKLY_REVIEW_AVAILABLE" ? await coachingService.reflectionDone(userId, now) : false;
    const subject = goal?.id ?? due?.action.id ?? null;
    const key = `${userId}:${trigger}:${subject ?? "-"}:${clock.localDate}`;

    // Konteks dari log keputusan sendiri (tanpa data klinis).
    const since7 = new Date(now.getTime() - 7 * 86_400_000);
    const delivered = consent ? await prisma.interventionDecision.findMany({ where: { userId, option: { not: "NO_INTERVENTION" }, deliveryStatus: { in: COUNTED }, decidedAt: { gte: since7 } }, orderBy: { decidedAt: "desc" } }) : [];
    // Jatah dan jeda hanya menghitung saran PROAKTIF; permintaan pengguna sendiri tidak memakai jatah.
    const sent = delivered.filter((d) => d.approvalStatus === "NOT_REQUIRED");
    const sameKey = delivered.filter((d) => d.triggerType === trigger && d.subjectRef === subject);
    const repeatSince = now.getTime() - REPEAT_SUPPRESS_DAYS * 86_400_000;
    const lastRating = delivered.find((d) => d.triggerType === trigger && (d.response === "NOT_USEFUL" || d.response === "USEFUL"));
    const result = decide({
      trigger,
      nowMs: now.getTime(),
      localMinute: clock.minute,
      consent,
      prefs: { pausedUntilMs: prefs.pausedUntil?.getTime() ?? null, quietStartMinute: prefs.quietStartMinute, quietEndMinute: prefs.quietEndMinute, maxPerDay: prefs.maxPerDay, maxPerWeek: prefs.maxPerWeek, mutedTriggers: prefs.mutedTriggers },
      hasActiveGoal: Boolean(goal),
      context: {
        deliveredToday: sent.filter((d) => d.localDate === clock.localDate).length,
        deliveredLast7Days: sent.length,
        lastDeliveredMs: sent[0]?.decidedAt.getTime() ?? null,
        sameKeyDeliveredMs: sameKey[0]?.decidedAt.getTime() ?? null,
        sameKeyRespondedToday: sameKey.some((d) => d.localDate === clock.localDate && d.response === "ALREADY_DONE") ? "ALREADY_DONE" : sameKey.some((d) => d.localDate === clock.localDate && d.response) ? "OTHER" : null,
        sameKeyUnrespondedWithinDays: sameKey.some((d) => d.decidedAt.getTime() >= repeatSince && d.response === null),
        snoozedUntilMs: sameKey.find((d) => d.deliveryStatus === "SNOOZED" && d.snoozedUntil)?.snoozedUntil?.getTime() ?? null,
      },
      coaching: trigger === "COACHING_ACTION_DUE" ? { due: Boolean(due), slotStarted: due?.slotStarted ?? false, safe: due?.safe ?? true } : undefined,
      review: trigger === "WEEKLY_REVIEW_AVAILABLE" ? { done: reviewDone } : undefined,
      recentNotUseful: lastRating?.response === "NOT_USEFUL",
    });

    // Permintaan berulang yang sama: kembalikan keputusan yang sudah ada, jangan buat baris baru.
    if (result.reason === "DUPLICATE" && sameKey[0]) return view(sameKey[0], true);

    const base = { userId, triggerType: trigger, subjectRef: subject, decidedAt: now, localDate: clock.localDate, timezone: tz, policyVersion: INTERVENTION_POLICY_VERSION, eligibilityStatus: result.option === "NO_INTERVENTION" ? "BLOCKED" : "ELIGIBLE", dataCoverage: result.coverage, option: result.option };
    try {
      const row = await prisma.interventionDecision.create({
        data:
          result.option === "NO_INTERVENTION"
            ? { ...base, reason: result.reason, approvalStatus: "NOT_REQUIRED", deliveryStatus: "NOT_APPLICABLE" }
            : { ...base, reason: null, approvalStatus: USER_INITIATED.has(trigger) ? "USER_INITIATED" : "NOT_REQUIRED", deliveryStatus: "ELIGIBLE", content: (result.option === "CLARIFICATION_QUESTION" ? CLARIFICATION_CONTENT : contentFor(trigger, due ? `${due.action.title}${due.action.slotLabel ? ` · ${due.action.slotLabel}` : ""}` : goal?.title)) as Prisma.InputJsonObject, dedupeKey: key, expiresAt: new Date(now.getTime() + EXPIRY_MS) },
      });
      return view(row);
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") {
        const existing = await prisma.interventionDecision.findUniqueOrThrow({ where: { dedupeKey: key } });
        return view(existing, true);
      }
      throw e;
    }
  },

  /** Kartu dalam aplikasi yang masih berlaku. Persetujuan dicek ulang saat dibaca; pencabutan membatalkan semuanya. */
  async listOpen(userId: string, now = new Date()) {
    if (!(await consentOk(userId))) {
      await prisma.interventionDecision.updateMany({ where: { userId, deliveryStatus: { in: OPEN } }, data: { deliveryStatus: "CANCELLED" } });
      return { items: [], consentRequired: true };
    }
    await prisma.interventionDecision.updateMany({ where: { userId, deliveryStatus: { in: OPEN }, expiresAt: { lt: now } }, data: { deliveryStatus: "EXPIRED" } });
    await prisma.interventionDecision.updateMany({ where: { userId, deliveryStatus: "SNOOZED", snoozedUntil: { lte: now }, expiresAt: { gte: now } }, data: { deliveryStatus: "DELIVERED", snoozedUntil: null } });
    await prisma.interventionDecision.updateMany({ where: { userId, deliveryStatus: "ELIGIBLE" }, data: { deliveryStatus: "DELIVERED" } });
    const rows = await prisma.interventionDecision.findMany({ where: { userId, deliveryStatus: "DELIVERED" }, orderBy: { decidedAt: "desc" }, take: 5 });
    return { items: rows.map((r) => view(r)), consentRequired: false };
  },

  /** Setiap jawaban punya akibat nyata. Jawaban pertama menang; mengulang jawaban yang sama aman. */
  async respond(userId: string, id: string, input: ResponseInput, now = new Date()) {
    if (!(await consentOk(userId))) throw forbidden("CONSENT_REQUIRED", "Persetujuan diperlukan.");
    const row = await prisma.interventionDecision.findFirst({ where: { id, userId } });
    if (!row) throw notFound("INTERVENTION_NOT_FOUND", "Saran tidak ditemukan.");
    if (row.option === "NO_INTERVENTION") throw unprocessable("NOTHING_TO_RESPOND", "Tidak ada saran untuk ditanggapi.");
    // Dibuka bukan tanggapan: kartu hilang dari daftar, tetapi pengguna masih boleh menilainya. Tidak berarti perilaku terjadi.
    if (input.kind === "OPENED") {
      if (row.deliveryStatus === "OPENED" || row.response) return view(row, true);
      if (!OPEN.includes(row.deliveryStatus)) throw conflict("INTERVENTION_NOT_OPEN", "Saran ini sudah tidak berlaku.", { status: row.deliveryStatus });
      await prisma.interventionDecision.updateMany({ where: { id, userId, response: null, deliveryStatus: { in: ["ELIGIBLE", "DELIVERED", "SNOOZED"] } }, data: { deliveryStatus: "OPENED" } });
      return view(await prisma.interventionDecision.findUniqueOrThrow({ where: { id } }));
    }
    if (row.response) {
      if (row.response === input.kind) return view(row, true);
      throw conflict("ALREADY_RESPONDED", "Saran ini sudah ditanggapi.", { response: row.response });
    }
    if (!OPEN.includes(row.deliveryStatus)) throw conflict("INTERVENTION_NOT_OPEN", "Saran ini sudah tidak berlaku.", { status: row.deliveryStatus });

    const snooze = input.kind === "NOT_NOW" ? new Date(now.getTime() + (input.snoozeMinutes ?? 120) * 60_000) : null;
    const updated = await prisma.$transaction(async (tx) => {
      const moved = await tx.interventionDecision.updateMany({
        where: { id, userId, response: null, deliveryStatus: { in: OPEN } },
        data: snooze ? { response: input.kind, respondedAt: now, deliveryStatus: "SNOOZED", snoozedUntil: snooze, expiresAt: new Date(Math.max(row.expiresAt?.getTime() ?? 0, snooze.getTime() + 2 * 3_600_000)) } : { response: input.kind, respondedAt: now, deliveryStatus: "RESPONDED" },
      });
      if (moved.count !== 1) throw conflict("ALREADY_RESPONDED", "Saran ini sudah ditanggapi.");
      if (input.kind === "STOP_THIS_TYPE") {
        const p = await tx.interventionPreference.findUnique({ where: { userId } });
        const muted = [...new Set([...(p?.mutedTriggers ?? []), row.triggerType])];
        await tx.interventionPreference.upsert({ where: { userId }, create: { userId, mutedTriggers: muted }, update: { mutedTriggers: muted } });
        await tx.interventionDecision.updateMany({ where: { userId, triggerType: row.triggerType, deliveryStatus: { in: OPEN }, id: { not: id } }, data: { deliveryStatus: "CANCELLED" } });
      }
      if (input.kind === "TOO_FREQUENT") {
        const p = await tx.interventionPreference.findUnique({ where: { userId } });
        const upd = { maxPerDay: Math.min(p?.maxPerDay ?? DEFAULTS.maxPerDay, 1), maxPerWeek: Math.min(p?.maxPerWeek ?? DEFAULTS.maxPerWeek, 3) };
        await tx.interventionPreference.upsert({ where: { userId }, create: { userId, ...upd }, update: upd });
      }
      await recordAudit(tx, { userId, eventType: "intervention_responded", metadata: { interventionId: id, kind: input.kind } });
      await outbox.enqueue(tx, { userId, type: "intervention.responded", payload: { interventionId: id, trigger: row.triggerType, kind: input.kind }, dedupeKey: `intervention-responded:${id}` });
      return tx.interventionDecision.findUniqueOrThrow({ where: { id } });
    });
    return view(updated);
  },

  async getPreferences(userId: string) {
    const p = await prefsOf(userId);
    return { pausedUntil: p.pausedUntil?.toISOString() ?? null, quietStartMinute: p.quietStartMinute, quietEndMinute: p.quietEndMinute, maxPerDay: p.maxPerDay, maxPerWeek: p.maxPerWeek, mutedTriggers: p.mutedTriggers, policyVersion: INTERVENTION_POLICY_VERSION };
  },

  async updatePreferences(userId: string, input: PreferencesInput, now = new Date()) {
    const data: Prisma.InterventionPreferenceUpdateInput = {};
    if (input.pauseForHours) data.pausedUntil = new Date(now.getTime() + input.pauseForHours * 3_600_000);
    if (input.resume) data.pausedUntil = null;
    if (input.quietStartMinute !== undefined) data.quietStartMinute = input.quietStartMinute;
    if (input.quietEndMinute !== undefined) data.quietEndMinute = input.quietEndMinute;
    if (input.maxPerDay !== undefined) data.maxPerDay = input.maxPerDay;
    if (input.maxPerWeek !== undefined) data.maxPerWeek = input.maxPerWeek;
    if (input.mutedTriggers) data.mutedTriggers = input.mutedTriggers;
    await prisma.interventionPreference.upsert({ where: { userId }, create: { userId, ...(data as object) }, update: data });
    if (input.pauseForHours) await prisma.interventionDecision.updateMany({ where: { userId, deliveryStatus: { in: OPEN }, option: { not: "NO_INTERVENTION" }, approvalStatus: "NOT_REQUIRED" }, data: { deliveryStatus: "CANCELLED" } });
    return this.getPreferences(userId);
  },
};
