import { background } from "../../shared/runtime/background.ts";
import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { outbox } from "../../infrastructure/queue/outbox.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { conflict, forbidden, notFound, unprocessable } from "../../shared/errors/app-error.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { ACTIVITY_COUNTED_QUALITY, activityWeek } from "../activity/activity.model.ts";
import { parseProfileData, type CoachingPrefs } from "../agent/personalization.ts";
import { consentService } from "../consent/consent.service.ts";
import { goalsService } from "../goals/goals.service.ts";
import { weeklyService } from "../insights/weekly.service.ts";
import { zonedToUtc } from "../medication/medication.model.ts";
import { featureFlags } from "../feature-flags/feature-flags.service.ts";
import { cohortService } from "../cohort/cohort.service.ts";
import { dailyFacts } from "../projections/daily-facts.service.ts";
import { isRecordedDay } from "../projections/daily-facts.model.ts";
import { memoryService } from "../memory/memory.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { MAX_ACTIVE_REMINDERS } from "../reminders/reminders.service.ts";
import { realtime } from "../../infrastructure/realtime/realtime.ts";
import { recognitionService } from "../community/recognition.service.ts";
import { notificationService } from "../notifications/notification.service.ts";
import * as M from "./coaching.model.ts";
import { BARRIER_LABEL, STRATEGIES, STRATEGY_CATALOG_VERSION, STRATEGY_DAYS, STRATEGY_REVIEW_STATUS, findStrategy, type Barrier, strategiesFor } from "./coaching.strategies.ts";
import { usageService } from "../usage/usage.service.ts";
import { episodesService } from "../episodes/episodes.service.ts";
import { isUnwell } from "../memory/memory.extract.ts";
import type { CheckinInput, ConfirmInput, DecisionInput, FeedbackInput } from "./coaching.schema.ts";

type Tx = Prisma.TransactionClient;
type ActionRow = Prisma.CoachingActionGetPayload<{ include: { outcomes: true; reminder: true } }>;

const iso = (d: Date) => d.toISOString().slice(0, 10);
const asDate = (s: string) => new Date(s + "T00:00:00Z");
const isUnique = (e: unknown) => e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002";
const OPEN_SOURCES_STATUS = ["ACCEPTED"];

async function hasConsent(userId: string, purposes: ("health_data_processing" | "personalized_ai" | "descriptive_summaries")[]) {
  try {
    for (const p of purposes) await consentService.requireConsent(userId, p);
    return true;
  } catch {
    return false;
  }
}
const fullConsent = (userId: string) => hasConsent(userId, ["health_data_processing", "personalized_ai"]);

async function clock(userId: string, now: Date) {
  const tz = (await preferencesService.get(userId)).timezone;
  const t = localRecordTime(now, tz);
  const [h, m] = (t.localTime ?? "00:00").split(":").map(Number);
  return { tz, today: t.localDate, minute: h! * 60 + m! };
}

async function prefsOf(userId: string, db: Tx | typeof prisma = prisma): Promise<CoachingPrefs> {
  const row = await db.personalizationProfile.findUnique({ where: { userId } });
  return row ? parseProfileData(row.data).coaching ?? {} : {};
}

async function updatePrefs(tx: Tx, userId: string, reason: string, actionId: string | null, mutate: (c: CoachingPrefs) => Record<string, unknown>) {
  await tx.personalizationProfile.upsert({ where: { userId }, create: { userId, version: 0, data: { dislikedTokens: {}, likedTokens: {} } }, update: {} });
  const row = await tx.personalizationProfile.findUniqueOrThrow({ where: { userId } });
  const data = parseProfileData(row.data);
  const coaching: CoachingPrefs = JSON.parse(JSON.stringify(data.coaching ?? {}));
  const change = mutate(coaching);
  data.coaching = coaching;
  const updated = await tx.personalizationProfile.update({ where: { userId }, data: { data: data as object, version: { increment: 1 } } });
  await tx.personalizationEvent.create({ data: { userId, version: updated.version, reason, change: JSON.parse(JSON.stringify({ rules: M.COACHING_RULES_VERSION, actionId, ...change })) } });
}

function snooze(c: CoachingPrefs, source: string, until: string) {
  c.snoozed = { ...(c.snoozed ?? {}), [source]: until };
  return { snoozed: { source, until } };
}

const slotOfMemory = (content: string) => {
  const w = content.match(/\b(pagi|siang|sore|malam)\b/);
  return w ? M.SLOT_FROM_WORD[w[1]!]! : null;
};

export async function gatherFacts(userId: string, tz: string, today: string, now: Date): Promise<M.Facts> {
  const start = (d: string) => zonedToUtc(d, "00:00", tz);
  const tomorrow = start(M.addDays(today, 1));
  const day = (d: Date) => localRecordTime(d, tz).localDate;
  const since7 = M.addDays(today, -6);
  const useProjection = await featureFlags.isEnabled("projection_consumers");
  const [user, meals, sessions, glucose, plans, coachingPlans, goalRows, memories, facts] = await Promise.all([
    prisma.users.findUnique({ where: { id: userId }, select: { createdAt: true } }),
    useProjection ? Promise.resolve([]) : prisma.mealLog.findMany({ where: { userId, archivedAt: null, consumedAt: { gte: start(M.addDays(today, -M.WINDOW_DAYS)), lt: tomorrow } }, select: { consumedAt: true, category: true } }),
    useProjection ? Promise.resolve([]) : prisma.activitySession.findMany({ where: { userId, archivedAt: null, qualityStatus: { in: [...ACTIVITY_COUNTED_QUALITY] }, startedAt: { gte: start(M.addDays(today, -28)), lt: tomorrow } }, select: { startedAt: true, durationMinutes: true } }),
    useProjection ? Promise.resolve([]) : prisma.glucoseObservation.findMany({ where: { userId, archivedAt: null, measuredAt: { gte: start(since7), lt: tomorrow } }, select: { measuredAt: true } }),
    prisma.activityPlan.findMany({ where: { userId, plannedFor: { gte: asDate(M.addDays(today, -M.WINDOW_DAYS)), lt: asDate(today) } }, select: { status: true, durationMinutes: true, recommendation: { select: { outcome: { select: { id: true } } } } } }),
    prisma.coachingAction.findMany({ where: { userId, kind: "ACTIVITY_SESSION", status: { in: ["ACCEPTED", "WITHDRAWN"] }, startDate: { gte: asDate(M.addDays(today, -M.WINDOW_DAYS - 7)) } }, include: { outcomes: true } }),
    prisma.behaviorGoal.findMany({ where: { userId, status: "active" }, orderBy: { createdAt: "desc" }, take: 10 }),
    memoryService.activeFor(userId),
    useProjection ? dailyFacts.list(userId, M.addDays(today, -28), today, tz) : Promise.resolve(null),
  ]);
  const mealsByDay: Record<string, string[]> = {};
  const recorded = new Set<string>();
  let longestSessionMinutes: number | null = null;
  if (facts) {
    const mealSince = M.addDays(today, -M.WINDOW_DAYS);
    for (const f of facts) {
      if (f.localDate >= mealSince && f.mealsLogged > 0) mealsByDay[f.localDate] = [...f.mealCategories];
      if (f.localDate >= since7 && isRecordedDay(f)) recorded.add(f.localDate);
      if (f.longestSessionMinutes !== null) longestSessionMinutes = Math.max(longestSessionMinutes ?? 0, f.longestSessionMinutes);
    }
  } else {
    for (const m of meals) (mealsByDay[day(m.consumedAt)] ??= []).push(m.category);
    for (const d of Object.keys(mealsByDay)) if (d >= since7) recorded.add(d);
    for (const s of sessions) if (day(s.startedAt) >= since7) recorded.add(day(s.startedAt));
    for (const g of glucose) recorded.add(day(g.measuredAt));
    longestSessionMinutes = sessions.length ? Math.max(...sessions.map((s) => s.durationMinutes)) : null;
  }

  let planned = 0, done = 0, notObserved = 0;
  const minutes: number[] = [];
  for (const p of plans) {
    planned++;
    minutes.push(p.durationMinutes);
    if (p.recommendation.outcome || p.status === "COMPLETED") done++;
    else notObserved++;
  }
  const windowStart = M.addDays(today, -M.WINDOW_DAYS);
  for (const a of coachingPlans) {
    const states = M.dayStates(iso(a.startDate), a.days, a.outcomes.map((o) => ({ localDate: iso(o.localDate), status: o.status as M.OutcomeRow["status"] })), today, true);
    const p = a.params as M.ActionParams;
    for (const s of states) {
      if (s.date >= today || s.date < windowStart) continue;
      planned++;
      if (p.durationMinutes) minutes.push(p.durationMinutes);
      if (s.state === "OBSERVED" || s.state === "USER_CONFIRMED") done++;
      else notObserved++;
    }
  }

  const goals: M.GoalFact[] = [];
  for (const g of goalRows) {
    const progress = await goalsService.progress(userId, g, today);
    const periodDays = g.period === "weekly" ? 7 : 1;
    goals.push({ id: g.id, title: g.title, goalType: g.goalType, period: g.period, target: g.targetValue.toNumber(), value: progress.value, elapsedDays: Math.min(periodDays, M.daysBetween(progress.periodStart, today) + 1), periodDays });
  }

  let availableMinutes: number | null = null;
  let preferredSlot: M.CoachingSlot | null = null;
  const dislikedTypes: string[] = [];
  for (const m of memories) {
    if (m.kind === "AVAILABLE_MINUTES") availableMinutes ??= Number(m.content.match(/(\d{1,3}) menit/)?.[1] ?? NaN) || null;
    if (m.kind === "ACTIVITY_TIME") preferredSlot ??= slotOfMemory(m.content);
    if (m.kind === "ACTIVITY_DISLIKE") dislikedTypes.push(m.key.split(":")[1] ?? "");
  }
  return {
    today,
    accountAgeDays: user ? Math.floor((now.getTime() - user.createdAt.getTime()) / 86_400_000) : 0,
    mealsByDay,
    recordedDays7: recorded.size,
    pastPlans: { planned, done, notObserved, avgMinutes: minutes.length ? minutes.reduce((s, v) => s + v, 0) / minutes.length : null },
    goals,
    longestSessionMinutes,
    memory: { availableMinutes, preferredSlot, dislikedTypes, used: memories.filter((m) => ["AVAILABLE_MINUTES", "ACTIVITY_TIME", "ACTIVITY_DISLIKE", "HEALTH_EVENT"].includes(m.kind)).map((m) => ({ id: m.id, content: m.content, kind: m.kind })), unwell: isUnwell(memories), avoidSlots: await episodesService.avoidSlots(userId, today) },
  };
}

function actionView(a: ActionRow, today: string, canObserve: boolean) {
  const start = iso(a.startDate);
  const outcomes = a.outcomes.map((o) => ({ localDate: iso(o.localDate), status: o.status as M.OutcomeRow["status"] }));
  const states = a.status === "PROPOSED" ? [] : M.dayStates(start, a.days, outcomes, today, canObserve && a.kind !== "HABIT_STEP");
  const end = M.addDays(start, a.days - 1);
  const count = (s: M.DayState) => states.filter((d) => d.state === s).length;
  return {
    id: a.id,
    source: a.source,
    kind: a.kind,
    title: a.title,
    rationale: a.rationale,
    evidence: a.evidence,
    params: a.params,
    slot: a.slot,
    slotLabel: a.slot ? M.SLOT_LABEL[a.slot as M.CoachingSlot] : null,
    startDate: start,
    endDate: end,
    days: a.days,
    status: a.status,
    phase: a.status === "ACCEPTED" ? (end < today ? "ENDED" : "RUNNING") : a.status,
    closeReason: a.closeReason,
    dayStates: states,
    summary: { observed: count("OBSERVED"), confirmed: count("USER_CONFIRMED"), notObserved: count("NOT_OBSERVED"), retracted: count("RETRACTED"), planned: count("PLANNED"), unknown: count("UNKNOWN") },
    reminder: a.reminder && !a.reminder.archivedAt ? { id: a.reminder.id, localTime: a.reminder.localTime, enabled: a.reminder.enabled } : null,
    expiresAt: a.expiresAt.toISOString(),
    decidedAt: a.decidedAt?.toISOString() ?? null,
    version: a.version,
    policyVersion: a.policyVersion,
  };
}

async function loadAction(userId: string, id: string, db: Tx | typeof prisma = prisma) {
  const a = await db.coachingAction.findFirst({ where: { id, userId }, include: { outcomes: true, reminder: true } });
  if (!a) throw notFound("COACHING_ACTION_NOT_FOUND", "Rencana tidak ditemukan.");
  return a;
}

const OPEN_CARDS = ["ELIGIBLE", "DELIVERED", "OPENED", "SNOOZED"];
async function closeCards(db: Tx | typeof prisma, userId: string, trigger: "COACHING_ACTION_DUE" | "WEEKLY_REVIEW_AVAILABLE", subjectRef?: string) {
  await db.interventionDecision.updateMany({ where: { userId, triggerType: trigger, deliveryStatus: { in: OPEN_CARDS }, ...(subjectRef ? { subjectRef } : {}) }, data: { deliveryStatus: "CANCELLED" } });
}

async function archiveReminder(tx: Tx, userId: string, reminderId: string | null, now: Date) {
  if (!reminderId) return;
  await tx.reminder.updateMany({ where: { id: reminderId, userId, archivedAt: null }, data: { archivedAt: now, enabled: false, version: { increment: 1 } } });
}

async function replayOf(userId: string, operationId: string, actionId: string | null, type: string, value: string) {
  const prior = await prisma.coachingEvent.findUnique({ where: { userId_operationId: { userId, operationId } } });
  if (!prior) return null;
  if (prior.actionId !== actionId || prior.type !== type || prior.value !== value) throw conflict("OPERATION_ID_REUSED", "operationId dipakai ulang untuk tindakan berbeda.");
  return prior;
}

async function evidenceFor(userId: string, tz: string, a: { kind: string; params: unknown }, dates: string[]) {
  const out = new Map<string, { type: "activity_session" | "meal_log"; id: string; at: Date }>();
  if (dates.length === 0) return out;
  const lo = zonedToUtc(dates[0]!, "00:00", tz), hi = zonedToUtc(M.addDays(dates.at(-1)!, 1), "00:00", tz);
  const params = a.params as M.ActionParams;
  const day = (d: Date) => localRecordTime(d, tz).localDate;
  if (a.kind === "ACTIVITY_SESSION") {
    const rows = await prisma.activitySession.findMany({ where: { userId, archivedAt: null, qualityStatus: { in: [...ACTIVITY_COUNTED_QUALITY] }, startedAt: { gte: lo, lt: hi } }, orderBy: { startedAt: "asc" }, select: { id: true, startedAt: true, activityType: true, durationMinutes: true } });
    for (const s of rows) if (M.matchesActivity(params, s) && !out.has(day(s.startedAt))) out.set(day(s.startedAt), { type: "activity_session", id: s.id, at: s.startedAt });
  } else {
    const rows = await prisma.mealLog.findMany({ where: { userId, archivedAt: null, consumedAt: { gte: lo, lt: hi } }, orderBy: { consumedAt: "asc" }, select: { id: true, consumedAt: true, category: true } });
    for (const m of rows) if (M.matchesMeal(params, m.category) && !out.has(day(m.consumedAt))) out.set(day(m.consumedAt), { type: "meal_log", id: m.id, at: m.consumedAt });
  }
  return out;
}

export const coachingService = {
  async reconcile(userId: string, now = new Date()) {
    const { tz, today } = await clock(userId, now);
    let observed = 0, retracted = 0;
    if (await fullConsent(userId)) {
      const actions = await prisma.coachingAction.findMany({ where: { userId, status: "ACCEPTED", kind: { not: "HABIT_STEP" }, startDate: { gte: asDate(M.addDays(today, -21)) } }, include: { outcomes: true } });
      for (const a of actions) {
        const dates = M.actionDates(iso(a.startDate), a.days).filter((d) => d <= today);
        const ev = await evidenceFor(userId, tz, a, dates);
        for (const date of dates) {
          const row = a.outcomes.find((o) => iso(o.localDate) === date);
          const hit = ev.get(date);
          try {
            if (hit && (!row || row.status !== "OBSERVED" || row.evidenceId !== hit.id)) {
              const data = { status: "OBSERVED", evidenceType: hit.type, evidenceId: hit.id, observedAt: hit.at };
              if (row) await prisma.coachingOutcome.update({ where: { id: row.id }, data });
              else await prisma.coachingOutcome.create({ data: { userId, actionId: a.id, localDate: asDate(date), ...data } });
              if (date === today) await closeCards(prisma, userId, "COACHING_ACTION_DUE", a.id);
              observed++;
            } else if (!hit && row?.status === "OBSERVED") {
              await prisma.coachingOutcome.update({ where: { id: row.id }, data: { status: "RETRACTED", evidenceType: null, evidenceId: null, observedAt: null } });
              retracted++;
            }
          } catch (e) {
            if (!isUnique(e)) throw e;
          }
        }
      }
    }
    await prisma.coachingAction.updateMany({ where: { userId, status: "PROPOSED", expiresAt: { lt: now } }, data: { status: "EXPIRED", closeReason: "EXPIRED", decidedAt: now, version: { increment: 1 } } });
    const linked = await prisma.coachingAction.findMany({ where: { userId, reminderId: { not: null }, reminder: { archivedAt: null } }, select: { status: true, startDate: true, days: true, reminderId: true } });
    const stale = linked.filter((a) => a.status !== "ACCEPTED" || M.addDays(iso(a.startDate), a.days - 1) < today).map((a) => a.reminderId!);
    if (stale.length) await prisma.reminder.updateMany({ where: { id: { in: stale }, userId, archivedAt: null }, data: { archivedAt: now, enabled: false, version: { increment: 1 } } });
    return { observed, retracted, remindersArchived: stale.length };
  },

  async opportunities(userId: string, now = new Date()) {
    if (!(await fullConsent(userId))) {
      await prisma.coachingAction.updateMany({ where: { userId, status: "PROPOSED" }, data: { status: "EXPIRED", closeReason: "CONSENT_WITHDRAWN", decidedAt: now, version: { increment: 1 } } });
      return { consentRequired: true, items: [], withheld: [], rulesVersion: M.COACHING_RULES_VERSION };
    }
    await this.reconcile(userId, now);
    const { tz, today } = await clock(userId, now);
    const [facts, prefs, running] = await Promise.all([
      gatherFacts(userId, tz, today, now),
      prefsOf(userId),
      prisma.coachingAction.findMany({ where: { userId, status: { in: OPEN_SOURCES_STATUS } }, select: { source: true, startDate: true, days: true } }),
    ]);
    const activeSources = new Set(running.filter((a) => M.addDays(iso(a.startDate), a.days - 1) >= today).map((a) => a.source));
    const sel = M.detectOpportunities(facts, { prefs, activeSources });
    const keys = new Set(sel.opportunities.map((o) => o.key));
    const open = await prisma.coachingAction.findMany({ where: { userId, status: "PROPOSED" } });
    const gone = open.filter((o) => !keys.has(o.opportunityKey)).map((o) => o.id);
    if (gone.length) await prisma.coachingAction.updateMany({ where: { id: { in: gone }, status: "PROPOSED" }, data: { status: "EXPIRED", closeReason: "NO_LONGER_SUPPORTED", decidedAt: now, version: { increment: 1 } } });
    const have = new Set(open.filter((o) => keys.has(o.opportunityKey)).map((o) => o.opportunityKey));
    for (const o of sel.opportunities) {
      if (have.has(o.key)) continue;
      try {
        await prisma.coachingAction.create({ data: { userId, opportunityKey: o.key, source: o.source, kind: o.kind, title: o.title, rationale: o.rationale, evidence: o.evidence as Prisma.InputJsonObject, params: o.params as Prisma.InputJsonObject, slot: o.slot, startDate: asDate(today), days: o.days, status: "PROPOSED", policyVersion: M.COACHING_RULES_VERSION, expiresAt: new Date(now.getTime() + M.PROPOSAL_TTL_MS) } });
        usageService.track(userId, "suggestion_offered", "coaching", { source: o.source.toLowerCase() });
      } catch (e) {
        if (!isUnique(e)) throw e;
      }
    }
    const rows = await prisma.coachingAction.findMany({ where: { userId, status: "PROPOSED", opportunityKey: { in: [...keys] } }, include: { outcomes: true, reminder: true } });
    const order = sel.opportunities.map((o) => o.key);
    rows.sort((a, b) => order.indexOf(a.opportunityKey) - order.indexOf(b.opportunityKey));
    return { consentRequired: false, items: rows.map((r) => actionView(r, today, true)), withheld: sel.withheld, rulesVersion: M.COACHING_RULES_VERSION };
  },

  async overview(userId: string, now = new Date()) {
    const opp = await this.opportunities(userId, now);
    const { today } = await clock(userId, now);
    const canObserve = !opp.consentRequired;
    const actions = await prisma.coachingAction.findMany({ where: { userId, status: "ACCEPTED", startDate: { gte: asDate(M.addDays(today, -14)) } }, include: { outcomes: true, reminder: true }, orderBy: [{ startDate: "desc" }, { createdAt: "desc" }] });
    const prefs = await prefsOf(userId);
    const reflection = opp.consentRequired ? null : await this.reflectionStatus(userId, now);
    return {
      consentRequired: opp.consentRequired,
      opportunities: opp.items,
      withheld: opp.withheld,
      actions: actions.map((a) => actionView(a, today, canObserve)),
      reflection,
      preferences: { slot: prefs.slot ?? null, muted: prefs.muted ?? [], maxSuggestions: prefs.maxSuggestions ?? M.DEFAULT_MAX_SUGGESTIONS },
      rulesVersion: M.COACHING_RULES_VERSION,
    };
  },

  async decide(userId: string, id: string, input: DecisionInput, now = new Date()) {
    if (input.decision !== "WITHDRAW" && !(await fullConsent(userId))) throw forbidden("CONSENT_REQUIRED", "Persetujuan diperlukan.");
    const { today } = await clock(userId, now);
    if (await replayOf(userId, input.operationId, id, "DECISION", input.decision)) return { ...actionView(await loadAction(userId, id), today, true), replayed: true };
    const a = await loadAction(userId, id);
    const expected = input.decision === "WITHDRAW" ? "ACCEPTED" : "PROPOSED";
    if (a.status !== expected) throw conflict("ACTION_NOT_OPEN", "Rencana ini sudah tidak bisa diubah.", { status: a.status });
    if (expected === "PROPOSED" && a.expiresAt < now) {
      await prisma.coachingAction.updateMany({ where: { id, status: "PROPOSED" }, data: { status: "EXPIRED", closeReason: "EXPIRED", decidedAt: now, version: { increment: 1 } } });
      throw conflict("ACTION_EXPIRED", "Usulan ini sudah kedaluwarsa.");
    }
    try {
      await prisma.$transaction(async (tx) => {
        const slot = input.slot ?? (a.slot as M.CoachingSlot | null);
        let reminderId: string | null = a.reminderId;
        const data: Prisma.CoachingActionUncheckedUpdateManyInput = { version: { increment: 1 }, decidedAt: input.decision === "WITHDRAW" ? a.decidedAt : now };
        if (input.decision === "ACCEPT") {
          const start = today;
          const dates = M.actionDates(start, a.days);
          if (input.reminder) {
            const active = await tx.reminder.count({ where: { userId, archivedAt: null } });
            if (active >= MAX_ACTIVE_REMINDERS) throw unprocessable("REMINDER_LIMIT", `Maksimal ${MAX_ACTIVE_REMINDERS} pengingat aktif.`);
            const r = await tx.reminder.create({ data: { userId, kind: a.kind === "ACTIVITY_SESSION" ? "activity" : "meal", title: a.title.slice(0, 80), localTime: input.reminder.localTime ?? M.SLOT_TIME[slot ?? "MIDDAY"], daysOfWeek: [...new Set(dates.map(M.isoWeekdayOf))].sort(), enabled: true } });
            reminderId = r.id;
            await recordAudit(tx, { userId, eventType: "reminder_created", metadata: { recordId: r.id, kind: r.kind, source: "coaching" } });
          }
          Object.assign(data, { status: "ACCEPTED", slot, startDate: asDate(start), reminderId });
        } else if (input.decision === "DECLINE") {
          Object.assign(data, { status: "DECLINED", closeReason: "DECLINED" });
          const variant = a.opportunityKey.split(":")[1] ?? "";
          await updatePrefs(tx, userId, "COACHING_DECLINED", a.id, (c) => {
            c.declinedVariants = { ...(c.declinedVariants ?? {}), [`${a.source}:${variant}`]: (c.declinedVariants?.[`${a.source}:${variant}`] ?? 0) + 1 };
            return { declinedVariant: `${a.source}:${variant}`, ...snooze(c, a.source, M.addDays(today, M.SNOOZE_DAYS.DECLINE)) };
          });
        } else {
          Object.assign(data, { status: "WITHDRAWN", closeReason: "USER_WITHDREW" });
          await archiveReminder(tx, userId, a.reminderId, now);
          await closeCards(tx, userId, "COACHING_ACTION_DUE", a.id);
        }
        const moved = await tx.coachingAction.updateMany({ where: { id, userId, status: expected, version: a.version }, data });
        if (moved.count !== 1) throw conflict("ACTION_NOT_OPEN", "Rencana ini sudah berubah. Muat ulang.");
        await tx.coachingEvent.create({ data: { userId, actionId: id, operationId: input.operationId, type: "DECISION", value: input.decision, detail: { slot: slot ?? null, reminder: Boolean(input.reminder) } } });
        await recordAudit(tx, { userId, eventType: "coaching_decided", metadata: { actionId: id, decision: input.decision, source: a.source } });
        await outbox.enqueue(tx, { userId, type: "coaching.decided", payload: { actionId: id, decision: input.decision, source: a.source }, dedupeKey: `coaching-decided:${userId}:${input.operationId}` });
      });
    } catch (e) {
      if (isUnique(e) && (await replayOf(userId, input.operationId, id, "DECISION", input.decision))) return { ...actionView(await loadAction(userId, id), today, true), replayed: true };
      throw e;
    }
    realtime.toUser(userId, { type: "coaching.updated", actionId: id });
    return { ...actionView(await loadAction(userId, id), today, true), replayed: false };
  },

  async feedback(userId: string, id: string, input: FeedbackInput, now = new Date()) {
    if (!(await hasConsent(userId, ["personalized_ai"]))) throw forbidden("CONSENT_REQUIRED", "Persetujuan diperlukan.");
    const { today } = await clock(userId, now);
    if (await replayOf(userId, input.operationId, id, "FEEDBACK", input.kind)) return { ...actionView(await loadAction(userId, id), today, true), replayed: true };
    const a = await loadAction(userId, id);
    const k = input.kind;
    const rating = k === "HELPFUL" || k === "NOT_HELPFUL";
    if (!rating && k !== "STOP_THIS_TYPE" && !["PROPOSED", "ACCEPTED"].includes(a.status)) throw conflict("ACTION_NOT_OPEN", "Rencana ini sudah tidak berjalan.", { status: a.status });
    if (rating) {
      const rated = await prisma.coachingEvent.findFirst({ where: { userId, actionId: id, type: "FEEDBACK", value: { in: ["HELPFUL", "NOT_HELPFUL"] } } });
      if (rated) throw conflict("FEEDBACK_ALREADY_RECORDED", "Penilaian untuk rencana ini sudah dicatat.", { kind: rated.value });
    }
    try {
      await prisma.$transaction(async (tx) => {
        const proposed = a.status === "PROPOSED";
        const accepted = a.status === "ACCEPTED";
        const close = async (closeReason: string) => {
          const status = proposed ? "DECLINED" : "WITHDRAWN";
          const moved = await tx.coachingAction.updateMany({ where: { id, userId, status: a.status, version: a.version }, data: { status, closeReason, decidedAt: proposed ? now : a.decidedAt, version: { increment: 1 } } });
          if (moved.count !== 1) throw conflict("ACTION_NOT_OPEN", "Rencana ini sudah berubah. Muat ulang.");
          if (accepted) {
            await archiveReminder(tx, userId, a.reminderId, now);
            await closeCards(tx, userId, "COACHING_ACTION_DUE", a.id);
          }
        };
        const variant = a.opportunityKey.split(":")[1] ?? "";
        switch (k) {
          case "HELPFUL":
          case "NOT_HELPFUL":
            await updatePrefs(tx, userId, `COACHING_${k}`, id, (c) => {
              const u = c.usefulness?.[a.source] ?? { helpful: 0, notHelpful: 0 };
              const next = k === "HELPFUL" ? { ...u, helpful: u.helpful + 1 } : { ...u, notHelpful: u.notHelpful + 1 };
              c.usefulness = { ...(c.usefulness ?? {}), [a.source]: next };
              return { usefulness: { source: a.source, from: u, to: next } };
            });
            break;
          case "ALREADY_DONE":
            if (proposed) {
              await close("ALREADY_DONE");
              await updatePrefs(tx, userId, "COACHING_ALREADY_DONE", id, (c) => snooze(c, a.source, M.addDays(today, M.SNOOZE_DAYS.ALREADY_DONE)));
            } else {
              const dates = M.actionDates(iso(a.startDate), a.days);
              if (!dates.includes(today)) throw unprocessable("DATE_NOT_IN_PLAN", "Hari ini tidak termasuk rencana ini.");
              await confirmDay(tx, userId, a.id, today);
              await closeCards(tx, userId, "COACHING_ACTION_DUE", a.id);
            }
            break;
          case "NOT_NOW":
            if (proposed) {
              await close("NOT_NOW");
              await updatePrefs(tx, userId, "COACHING_NOT_NOW", id, (c) => snooze(c, a.source, M.addDays(today, M.SNOOZE_DAYS.NOT_NOW)));
            }
            break;
          case "TOO_FREQUENT": {
            const p = await tx.interventionPreference.findUnique({ where: { userId } });
            const upd = { maxPerDay: Math.min(p?.maxPerDay ?? 2, 1), maxPerWeek: Math.min(p?.maxPerWeek ?? 7, 3) };
            await tx.interventionPreference.upsert({ where: { userId }, create: { userId, ...upd }, update: upd });
            if (proposed) await close("TOO_FREQUENT");
            await updatePrefs(tx, userId, "COACHING_TOO_FREQUENT", id, (c) => {
              const from = c.maxSuggestions ?? M.DEFAULT_MAX_SUGGESTIONS;
              c.maxSuggestions = 1;
              return { maxSuggestions: { from, to: 1 }, interventions: upd, ...(proposed ? snooze(c, a.source, M.addDays(today, M.SNOOZE_DAYS.TOO_FREQUENT)) : {}) };
            });
            break;
          }
          case "PREFER_DIFFERENT_TIME": {
            const slot = input.slot!;
            const moved = await tx.coachingAction.updateMany({ where: { id, userId, status: a.status, version: a.version }, data: { slot, version: { increment: 1 } } });
            if (moved.count !== 1) throw conflict("ACTION_NOT_OPEN", "Rencana ini sudah berubah. Muat ulang.");
            if (accepted && a.reminderId) await tx.reminder.updateMany({ where: { id: a.reminderId, userId, archivedAt: null }, data: { localTime: M.SLOT_TIME[slot], version: { increment: 1 } } });
            await updatePrefs(tx, userId, "COACHING_PREFER_DIFFERENT_TIME", id, (c) => {
              const from = c.slot ?? null;
              c.slot = slot;
              return { slot: { from, to: slot } };
            });
            break;
          }
          case "PREFER_DIFFERENT_SUGGESTION":
            await close("DIFFERENT_SUGGESTION");
            await updatePrefs(tx, userId, "COACHING_PREFER_DIFFERENT_SUGGESTION", id, (c) => {
              const key = `${a.source}:${variant}`;
              c.declinedVariants = { ...(c.declinedVariants ?? {}), [key]: (c.declinedVariants?.[key] ?? 0) + 1 };
              return { declinedVariant: key };
            });
            break;
          case "STOP_THIS_TYPE":
            if (proposed || accepted) await close("STOPPED_BY_USER");
            await tx.coachingAction.updateMany({ where: { userId, source: a.source, status: "PROPOSED", id: { not: id } }, data: { status: "DECLINED", closeReason: "STOPPED_BY_USER", decidedAt: now, version: { increment: 1 } } });
            await updatePrefs(tx, userId, "COACHING_STOP_THIS_TYPE", id, (c) => {
              c.muted = [...new Set([...(c.muted ?? []), a.source])];
              return { muted: a.source };
            });
            break;
        }
        await tx.coachingEvent.create({ data: { userId, actionId: id, operationId: input.operationId, type: "FEEDBACK", value: k, ...(input.slot ? { detail: { slot: input.slot } } : {}) } });
        await recordAudit(tx, { userId, eventType: "coaching_feedback", metadata: { actionId: id, kind: k, source: a.source } });
        await outbox.enqueue(tx, { userId, type: "coaching.feedback", payload: { actionId: id, kind: k, source: a.source }, dedupeKey: `coaching-feedback:${userId}:${input.operationId}` });
      });
    } catch (e) {
      if (isUnique(e) && (await replayOf(userId, input.operationId, id, "FEEDBACK", input.kind))) return { ...actionView(await loadAction(userId, id), today, true), replayed: true };
      throw e;
    }
    realtime.toUser(userId, { type: "coaching.updated", actionId: id });
    return { ...actionView(await loadAction(userId, id), today, true), replayed: false };
  },

  async confirm(userId: string, id: string, input: ConfirmInput, now = new Date()) {
    if (!(await fullConsent(userId))) throw forbidden("CONSENT_REQUIRED", "Persetujuan diperlukan.");
    const { today } = await clock(userId, now);
    if (await replayOf(userId, input.operationId, id, "CONFIRMATION", input.date)) return { ...actionView(await loadAction(userId, id), today, true), replayed: true };
    const a = await loadAction(userId, id);
    if (a.status !== "ACCEPTED") throw conflict("ACTION_NOT_OPEN", "Hanya rencana yang kamu terima yang bisa dikonfirmasi.", { status: a.status });
    if (!M.actionDates(iso(a.startDate), a.days).includes(input.date) || input.date > today) throw unprocessable("DATE_NOT_IN_PLAN", "Tanggal ini tidak termasuk rencana atau belum terjadi.");
    try {
      await prisma.$transaction(async (tx) => {
        await confirmDay(tx, userId, id, input.date);
        if (input.date === today) await closeCards(tx, userId, "COACHING_ACTION_DUE", id);
        await tx.coachingEvent.create({ data: { userId, actionId: id, operationId: input.operationId, type: "CONFIRMATION", value: input.date } });
        await recordAudit(tx, { userId, eventType: "coaching_confirmed", metadata: { actionId: id, date: input.date } });
      });
    } catch (e) {
      if (isUnique(e) && (await replayOf(userId, input.operationId, id, "CONFIRMATION", input.date))) return { ...actionView(await loadAction(userId, id), today, true), replayed: true };
      throw e;
    }
    realtime.toUser(userId, { type: "coaching.updated", actionId: id });
    return { ...actionView(await loadAction(userId, id), today, true), replayed: false };
  },

  async dueToday(userId: string, now = new Date()) {
    await this.reconcile(userId, now);
    const { tz, today, minute } = await clock(userId, now);
    const rows = await prisma.coachingAction.findMany({ where: { userId, status: "ACCEPTED", startDate: { lte: asDate(today), gte: asDate(M.addDays(today, -7)) } }, include: { outcomes: true, reminder: true }, orderBy: { createdAt: "asc" } });
    const due = rows.find((a) => M.actionDates(iso(a.startDate), a.days).includes(today) && !a.outcomes.some((o) => iso(o.localDate) === today && o.status !== "RETRACTED"));
    if (!due) return null;
    const slot = due.slot as M.CoachingSlot | null;
    let safe = true;
    if (due.kind === "ACTIVITY_SESSION") {
      const [longest, memories] = await Promise.all([
        prisma.activitySession.aggregate({ where: { userId, archivedAt: null, qualityStatus: { in: [...ACTIVITY_COUNTED_QUALITY] }, startedAt: { gte: zonedToUtc(M.addDays(today, -28), "00:00", tz) } }, _max: { durationMinutes: true } }),
        memoryService.activeFor(userId),
      ]);
      const disliked = memories.filter((m) => m.kind === "ACTIVITY_DISLIKE").map((m) => m.key.split(":")[1] ?? "");
      safe = M.validateOpportunity({ kind: "ACTIVITY_SESSION", params: due.params as M.ActionParams, days: due.days }, { longestSessionMinutes: longest._max.durationMinutes, memory: { availableMinutes: null, preferredSlot: null, dislikedTypes: disliked, used: [] } }) === null;
    }
    return { action: { id: due.id, title: due.title, slot, slotLabel: slot ? M.SLOT_LABEL[slot] : null }, slotStarted: slot ? minute >= M.SLOT_START_MINUTE[slot] : true, safe };
  },

  async reflectionWeek(userId: string, now = new Date()) {
    const p = await preferencesService.get(userId);
    const today = localRecordTime(now, p.timezone).localDate;
    return M.reflectionWeekStart(today, activityWeek(today, p.locale).startDate);
  },

  async reflectionDone(userId: string, now = new Date()) {
    const week = await this.reflectionWeek(userId, now);
    return Boolean(await prisma.weeklyCheckin.findUnique({ where: { userId_weekStart: { userId, weekStart: asDate(week) } }, select: { id: true } }));
  },

  async reflectionStatus(userId: string, now = new Date()) {
    if (!(await hasConsent(userId, ["health_data_processing", "descriptive_summaries"]))) return null;
    const { today } = await clock(userId, now);
    const current = await weeklyService.get(userId, today);
    const target = M.reflectionWeekStart(today, current.weekStart);
    const week = target === current.weekStart ? current : await weeklyService.get(userId, target);
    const done = await prisma.weeklyCheckin.findUnique({ where: { userId_weekStart: { userId, weekStart: asDate(target) } }, select: { id: true } });
    const actions = await prisma.coachingAction.count({ where: { userId, status: { in: ["ACCEPTED", "WITHDRAWN"] }, startDate: { lte: asDate(week.weekEnd), gte: asDate(M.addDays(target, -6)) } } });
    return { weekStart: target, weekEnd: week.weekEnd, done: Boolean(done), available: week.recordedDays > 0 || actions > 0 };
  },

  async reflection(userId: string, now = new Date(), opts: { currentWeek?: boolean } = {}) {
    if (!(await hasConsent(userId, ["health_data_processing", "descriptive_summaries"]))) return { consentRequired: true as const };
    await this.reconcile(userId, now);
    const { tz, today } = await clock(userId, now);
    const current = await weeklyService.get(userId, today);
    const target = opts.currentWeek ? current.weekStart : M.reflectionWeekStart(today, current.weekStart);
    const week = target === current.weekStart ? current : await weeklyService.get(userId, target);
    const weekEnd = week.weekEnd;
    const asOf = target === current.weekStart ? today : weekEnd;
    const daysSoFar = target === current.weekStart ? Math.min(week.totalDays, M.daysBetween(target, today) + 1) : week.totalDays;
    const [checkin, history, actionRows, agentOutcomes, goalRows] = await Promise.all([
      prisma.weeklyCheckin.findUnique({ where: { userId_weekStart: { userId, weekStart: asDate(target) } } }),
      prisma.weeklyCheckin.findMany({ where: { userId }, orderBy: { weekStart: "desc" }, take: 12 }),
      prisma.coachingAction.findMany({ where: { userId, status: { in: ["ACCEPTED", "WITHDRAWN"] }, startDate: { lte: asDate(weekEnd), gte: asDate(M.addDays(target, -6)) } }, include: { outcomes: true, reminder: true }, orderBy: { startDate: "asc" } }),
      prisma.recommendationOutcome.count({ where: { userId, observedAt: { gte: zonedToUtc(target, "00:00", tz), lt: zonedToUtc(M.addDays(weekEnd, 1), "00:00", tz) } } }),
      prisma.behaviorGoal.findMany({ where: { userId, status: "active" }, orderBy: { createdAt: "desc" }, take: 10 }),
    ]);
    const items = actionRows.map((a) => {
      const v = actionView(a, today, true);
      const states = v.dayStates.filter((d) => d.date >= target && d.date <= weekEnd);
      return { id: a.id, title: a.title, kind: a.kind, status: a.status, dayStates: states };
    }).filter((a) => a.dayStates.length > 0);
    const all = items.flatMap((a) => a.dayStates);
    const tally = { observed: all.filter((d) => d.state === "OBSERVED").length, confirmed: all.filter((d) => d.state === "USER_CONFIRMED").length, notObserved: all.filter((d) => d.state === "NOT_OBSERVED" || d.state === "RETRACTED").length, planned: all.filter((d) => d.state === "PLANNED").length };
    const actionsDone = tally.observed + tally.confirmed + agentOutcomes;
    const goals: (M.GoalWeek & { ratio: number | null; period: string })[] = [];
    for (const g of goalRows) {
      const p = await goalsService.progress(userId, g, asOf);
      const history: (number | null)[] = [];
      if (g.period === "weekly") for (let k = 1; k <= 3; k++) history.push((await goalsService.progress(userId, g, M.addDays(target, -7 * k))).value);
      goals.push({ id: g.id, title: g.title, goalType: g.goalType, period: g.period, target: g.targetValue.toNumber(), value: p.value, version: g.version, ratio: p.ratio, history });
    }
    const stepAdjustments: M.Adjustment[] = [];
    for (const g of goalRows.filter((x) => x.goalType === "daily_steps" && x.period === "daily")) {
      const fromDay = M.addDays(asOf, -(M.STEPS_WINDOW_DAYS - 1));
      const rows = await prisma.dailySteps.findMany({ where: { userId, localDate: { gte: asDate(fromDay), lte: asDate(asOf) } } });
      const byDay = new Map(rows.map((r) => [iso(r.localDate), r.steps]));
      const last = Array.from({ length: M.STEPS_WINDOW_DAYS }, (_, i) => byDay.get(M.addDays(fromDay, i)) ?? null);
      const adj = M.dailyStepsAdjustment({ id: g.id, title: g.title, target: g.targetValue.toNumber(), version: g.version }, last);
      if (adj) stepAdjustments.push(adj);
    }
    const lastStrategy = await prisma.coachingAction.findFirst({ where: { userId, source: "PROBLEM_SOLVING", opportunityKey: { not: `PROBLEM_SOLVING:${STRATEGY_DAYS}d:${target}` } }, orderBy: { createdAt: "desc" }, include: { outcomes: true, reminder: true } });
    const previousStrategy = lastStrategy
      ? (() => {
          const v = actionView(lastStrategy, today, false);
          const p = lastStrategy.params as { barrier?: Barrier };
          return { id: v.id, title: v.title, barrier: p.barrier ?? null, barrierLabel: p.barrier ? BARRIER_LABEL[p.barrier] : null, startDate: v.startDate, endDate: v.endDate, days: v.days, confirmedDays: v.summary.confirmed, status: v.status };
        })()
      : null;
    const previous = history.some((h) => iso(h.weekStart) === M.addDays(target, -7));
    const positives = M.positiveObservations({
      mealDays: week.meals.daysWithRecords,
      activityMinutes: week.activity.totalMinutes,
      activityDays: week.activity.daysWithRecords,
      recordedDays: week.recordedDays,
      totalDays: daysSoFar,
      actionsDone,
      goalsReached: goals.filter((g) => g.period === "weekly" && (g.ratio ?? 0) >= 1).map((g) => g.title),
      previousReflection: previous,
    });
    if (previousStrategy && previousStrategy.confirmedDays > 0) positives.push(`Strategi “${previousStrategy.title}” kamu jalankan ${previousStrategy.confirmedDays} hari`);
    const prefs = await prefsOf(userId);
    const memories = await memoryService.activeFor(userId);
    const memorySlot = memories.find((m) => m.kind === "ACTIVITY_TIME");
    const weeks = history.map((h) => iso(h.weekStart));
    return {
      consentRequired: false as const,
      weekStart: target,
      weekEnd,
      isCurrentWeek: target === current.weekStart,
      done: checkin ? checkinView(checkin) : null,
      summary: { recordedDays: week.recordedDays, totalDays: daysSoFar, coverageStatus: week.coverageStatus, meals: { daysWithRecords: week.meals.daysWithRecords }, activity: { totalMinutes: week.activity.totalMinutes, daysWithRecords: week.activity.daysWithRecords }, glucose: { daysWithRecords: week.glucose.daysWithRecords } },
      goals: goals.map((g) => ({ id: g.id, title: g.title, goalType: g.goalType, period: g.period, target: g.target, value: g.value, ratio: g.ratio })),
      actions: { ...tally, fromAssistant: agentOutcomes, items },
      positives,
      adjustments: [...M.goalAdjustments(goals), ...stepAdjustments],
      strategies: { catalogVersion: STRATEGY_CATALOG_VERSION, reviewStatus: STRATEGY_REVIEW_STATUS, byBarrier: strategiesFor(await cohortService.journeyOf(userId)), labels: BARRIER_LABEL },
      learned: await episodesService.build(userId, target),
      memoryBarriers: memories.filter((m) => m.kind === "BARRIER").map((m) => m.key.split(":")[1]).filter((b): b is string => ["TIME", "FORGOT", "ENERGY", "MOTIVATION", "OTHER"].includes(b ?? "")),
      previousStrategy,
      streak: M.streakOf(weeks, checkin ? target : M.addDays(target, -7)),
      history: history.slice(0, 8).map(checkinView),
      memoryAvailable: await memoryService.allowed(userId),
      preferredSlot: prefs.slot ?? (memorySlot ? slotOfMemory(memorySlot.content) : null),
      nudge: !checkin && (week.recordedDays > 0 || items.length > 0),
      computedFrom: { weekly: week.computationVersion, rules: M.COACHING_RULES_VERSION },
    };
  },

  async submitCheckin(userId: string, input: CheckinInput, now = new Date()) {
    const prior = await prisma.weeklyCheckin.findUnique({ where: { userId_operationId: { userId, operationId: input.operationId } } });
    if (prior) {
      if (iso(prior.weekStart) !== input.weekStart) throw conflict("OPERATION_ID_REUSED", "operationId dipakai ulang untuk minggu berbeda.");
      return { checkin: checkinView(prior), recognition: (prior.summary as { recognition?: string[] }).recognition ?? [], replayed: true };
    }
    const r = await this.reflection(userId, now);
    if (r.consentRequired) throw forbidden("CONSENT_REQUIRED", "Persetujuan diperlukan.");
    if (input.weekStart !== r.weekStart) throw unprocessable("WEEK_NOT_OPEN", "Refleksi untuk minggu ini belum atau sudah tidak dibuka.", { weekStart: r.weekStart });
    if (r.done) throw conflict("CHECKIN_EXISTS", "Refleksi untuk minggu ini sudah tersimpan.");
    const offered = new Map(r.adjustments.map((a) => [a.goalId, a]));
    for (const adj of input.adjustments) {
      const o = offered.get(adj.goalId);
      if (!o || o.toTarget !== adj.toTarget) throw unprocessable("ADJUSTMENT_NOT_OFFERED", "Penyesuaian ini tidak sesuai dengan usulan.", { goalId: adj.goalId });
    }
    const strategy = input.strategy ? findStrategy(input.strategy.barrier, input.strategy.key) : null;
    if (input.strategy && !strategy) throw unprocessable("STRATEGY_NOT_OFFERED", "Strategi ini tidak ada di daftar.", { key: input.strategy.key });
    const { today: localToday } = await clock(userId, now);
    const personal = await hasConsent(userId, ["personalized_ai"]);
    const remember = Boolean(input.rememberSlot && input.preferredSlot && (await memoryService.allowed(userId)));
    const streak = M.streakOf([...r.history.map((h) => h.weekStart), r.weekStart], r.weekStart);
    const recognition = M.recognitions({ streak, actionsDone: r.actions.observed + r.actions.confirmed + r.actions.fromAssistant, recordedDays: r.summary.recordedDays });
    try {
      const saved = await prisma.$transaction(async (tx) => {
        const applied: M.Adjustment[] = [];
        for (const adj of input.adjustments) {
          const o = offered.get(adj.goalId)!;
          const g = await tx.behaviorGoal.findFirst({ where: { id: o.goalId, userId } });
          if (!g || g.version !== o.expectedVersion) throw conflict("VERSION_CONFLICT", "Tujuan berubah. Muat ulang refleksi.");
          const moved = await tx.behaviorGoal.updateMany({ where: { id: g.id, userId, version: g.version }, data: { targetValue: o.toTarget, version: { increment: 1 } } });
          if (moved.count !== 1) throw conflict("VERSION_CONFLICT", "Tujuan berubah. Muat ulang refleksi.");
          await tx.recordRevision.create({ data: { userId, goalId: g.id, version: g.version, reason: o.direction === "UP" ? "Refleksi mingguan: target dinaikkan atas persetujuan pengguna" : "Refleksi mingguan: target diturunkan atas persetujuan pengguna", snapshot: { title: g.title, goalType: g.goalType, targetValue: g.targetValue.toNumber(), period: g.period, status: g.status, version: g.version } } });
          await recordAudit(tx, { userId, eventType: "goal_updated", metadata: { recordId: g.id, version: g.version + 1, source: "weekly_reflection", direction: o.direction, fromTarget: o.fromTarget, toTarget: o.toTarget, rules: M.COACHING_RULES_VERSION } });
          applied.push(o);
        }
        if (input.preferredSlot && personal) {
          await updatePrefs(tx, userId, "COACHING_REFLECTION_SLOT", null, (c) => {
            const from = c.slot ?? null;
            c.slot = input.preferredSlot!;
            return { slot: { from, to: input.preferredSlot } };
          });
        }
        if (remember) {
          const content = `Lebih suka beraktivitas ${M.SLOT_LABEL[input.preferredSlot!]} hari`;
          const active = await tx.memoryItem.findFirst({ where: { userId, key: "ACTIVITY_TIME", status: "ACTIVE" } });
          if (active) {
            if (active.content !== content) await tx.memoryItem.update({ where: { id: active.id }, data: { content, version: { increment: 1 }, confirmedAt: now, sourceType: "USER" } });
          } else {
            await tx.memoryItem.create({ data: { userId, category: "PREFERENCE", kind: "ACTIVITY_TIME", key: "ACTIVITY_TIME", content, status: "ACTIVE", sourceType: "USER", confirmedAt: now } });
          }
          await recordAudit(tx, { userId, eventType: "memory_confirmed", metadata: { kind: "ACTIVITY_TIME", source: "weekly_reflection" } });
        }
        const row = await tx.weeklyCheckin.create({
          data: {
            userId,
            weekStart: asDate(r.weekStart),
            operationId: input.operationId,
            mood: input.mood ?? null,
            hardest: input.hardest,
            note: input.note ?? null,
            preferredSlot: input.preferredSlot ?? null,
            adjustments: applied.map((a) => ({ goalId: a.goalId, title: a.title, fromTarget: a.fromTarget, toTarget: a.toTarget, direction: a.direction })),
            summary: { recordedDays: r.summary.recordedDays, totalDays: r.summary.totalDays, positives: r.positives, actions: { observed: r.actions.observed, confirmed: r.actions.confirmed, notObserved: r.actions.notObserved, fromAssistant: r.actions.fromAssistant }, recognition, rememberedSlot: remember, strategy: strategy && input.strategy ? { barrier: input.strategy.barrier, key: strategy.key, catalogVersion: STRATEGY_CATALOG_VERSION } : null, adjustmentDirections: applied.map((a) => a.direction) },
          },
        });
        if (strategy && input.strategy) {
          const action = await tx.coachingAction.create({
            data: {
              userId,
              opportunityKey: `PROBLEM_SOLVING:${STRATEGY_DAYS}d:${r.weekStart}`,
              source: "PROBLEM_SOLVING",
              kind: "HABIT_STEP",
              title: strategy.title.slice(0, 120),
              rationale: `Rencana dari refleksi untuk hambatan “${BARRIER_LABEL[input.strategy.barrier]}”. ${strategy.detail}`.slice(0, 400),
              evidence: { summary: `Kamu memilih hambatan “${BARRIER_LABEL[input.strategy.barrier]}” di refleksi minggu ${r.weekStart}.`, window: "refleksi mingguan", memories: [], barrier: input.strategy.barrier, strategyKey: strategy.key, catalogVersion: STRATEGY_CATALOG_VERSION, reviewStatus: STRATEGY_REVIEW_STATUS },
              params: { barrier: input.strategy.barrier, strategyKey: strategy.key },
              startDate: asDate(localToday),
              days: STRATEGY_DAYS,
              status: "ACCEPTED",
              policyVersion: M.COACHING_RULES_VERSION,
              expiresAt: now,
              decidedAt: now,
            },
          });
          await tx.coachingEvent.create({ data: { userId, actionId: action.id, operationId: input.operationId, type: "DECISION", value: "ACCEPT", detail: { source: "PROBLEM_SOLVING", strategyKey: strategy.key, barrier: input.strategy.barrier } } });
          await recordAudit(tx, { userId, eventType: "coaching_strategy_chosen", metadata: { actionId: action.id, barrier: input.strategy.barrier, strategyKey: strategy.key } });
        }
        await closeCards(tx, userId, "WEEKLY_REVIEW_AVAILABLE");
        await recordAudit(tx, { userId, eventType: "weekly_reflection_completed", metadata: { checkinId: row.id, adjustments: applied.length } });
        await outbox.enqueue(tx, { userId, type: "coaching.checkin", payload: { checkinId: row.id, weekStart: r.weekStart }, dedupeKey: `coaching-checkin:${row.id}` });
        return row;
      });
      realtime.toUser(userId, { type: "coaching.updated", checkinId: saved.id });
      background(recognitionService.refresh(userId), "recognition_refresh");
      return { checkin: checkinView(saved), recognition, replayed: false };
    } catch (e) {
      if (isUnique(e)) {
        const again = await prisma.weeklyCheckin.findUnique({ where: { userId_operationId: { userId, operationId: input.operationId } } });
        if (again) return { checkin: checkinView(again), recognition: (again.summary as { recognition?: string[] }).recognition ?? [], replayed: true };
        throw conflict("CHECKIN_EXISTS", "Refleksi untuk minggu ini sudah tersimpan.");
      }
      throw e;
    }
  },

  async nudgeReflections(now = new Date()) {
    const since = new Date(now.getTime() - 7 * 86_400_000);
    const users = await prisma.mealLog.findMany({ where: { archivedAt: null, consumedAt: { gte: since } }, distinct: ["userId"], select: { userId: true }, take: 500 });
    let sent = 0;
    for (const { userId } of users) {
      const { minute } = await clock(userId, now);
      if (minute < 18 * 60) continue;
      if (!(await hasConsent(userId, ["health_data_processing", "descriptive_summaries", "personalized_ai"]))) continue;
      const status = await this.reflectionStatus(userId, now);
      if (!status || status.done || !status.available) continue;
      const made = await notificationService.notify(userId, { kind: "REFLECTION", title: "Refleksi mingguan siap", body: "Lihat yang sudah berjalan dan atur langkah minggu depan. Sekitar 2 menit.", action: "OPEN_REFLECTION", refId: status.weekStart, dedupeKey: `reflection:${status.weekStart}` });
      if (made) sent++;
    }
    return { candidates: users.length, sent };
  },
};

async function confirmDay(tx: Tx, userId: string, actionId: string, date: string) {
  const row = await tx.coachingOutcome.findUnique({ where: { actionId_localDate: { actionId, localDate: asDate(date) } } });
  if (row?.status === "OBSERVED" || row?.status === "USER_CONFIRMED") return;
  if (row) await tx.coachingOutcome.update({ where: { id: row.id }, data: { status: "USER_CONFIRMED" } });
  else await tx.coachingOutcome.create({ data: { userId, actionId, localDate: asDate(date), status: "USER_CONFIRMED" } });
}

function checkinView(c: Awaited<ReturnType<typeof prisma.weeklyCheckin.findFirstOrThrow>>) {
  return { id: c.id, weekStart: iso(c.weekStart), mood: c.mood, hardest: c.hardest, note: c.note, preferredSlot: c.preferredSlot, adjustments: c.adjustments, summary: c.summary, createdAt: c.createdAt.toISOString() };
}
