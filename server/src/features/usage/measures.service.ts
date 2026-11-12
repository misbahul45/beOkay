import { prisma } from "../../infrastructure/database/prisma.ts";
import { currentPolicy } from "../consent/consent.policy.ts";
import { median } from "./usage.model.ts";

export const MEASURES_VERSION = "measures-v1";
const DAY = 86_400_000;

type Range = { from: Date; to: Date };
const round = (v: number | null, d = 3) => (v === null || !Number.isFinite(v) ? null : Math.round(v * 10 ** d) / 10 ** d);
const ratio = (a: number, b: number) => (b === 0 ? null : round(a / b));

async function cohort() {
  const rows = await prisma.consentRecord.findMany({ where: { purpose: "product_analytics", withdrawnAt: null, policyVersion: currentPolicy.version }, select: { userId: true }, distinct: ["userId"] });
  return rows.map((r) => r.userId);
}

export const measuresService = {
  async compute(range: Range) {
    const users = await cohort();
    const where = { userId: { in: users }, occurredAt: { gte: range.from, lt: range.to } };
    const days = Math.max(1, Math.round((range.to.getTime() - range.from.getTime()) / DAY));

    const daily = users.length
      ? await prisma.$queryRaw<{ day: string; users: bigint }[]>`SELECT to_char(date_trunc('day', occurred_at AT TIME ZONE 'Asia/Jakarta'), 'YYYY-MM-DD') AS day, count(DISTINCT user_id) AS users FROM usage_events WHERE user_id = ANY(${users}::uuid[]) AND occurred_at >= ${range.from} AND occurred_at < ${range.to} GROUP BY 1`
      : [];
    const dau = daily.length ? daily.reduce((s, r) => s + Number(r.users), 0) / days : 0;
    const wau = (await prisma.usageEvent.findMany({ where: { userId: { in: users }, occurredAt: { gte: new Date(range.to.getTime() - 7 * DAY), lt: range.to } }, distinct: ["userId"], select: { userId: true } })).length;

    const recordDays = users.length
      ? await prisma.$queryRaw<{ user_id: string; days: bigint }[]>`SELECT user_id, count(DISTINCT date_trunc('day', occurred_at AT TIME ZONE 'Asia/Jakarta')) AS days FROM usage_events WHERE user_id = ANY(${users}::uuid[]) AND event_type = 'record_created' AND occurred_at >= ${range.from} AND occurred_at < ${range.to} GROUP BY 1`
      : [];
    const perWeek = recordDays.map((r) => (Number(r.days) * 7) / days);

    const created = await prisma.users.findMany({ where: { id: { in: users }, createdAt: { lt: new Date(range.to.getTime() - 28 * DAY) } }, select: { id: true, createdAt: true } });
    let retained = 0;
    for (const u of created) {
      const hit = await prisma.usageEvent.findFirst({ where: { userId: u.id, eventType: "record_created", occurredAt: { gte: new Date(u.createdAt.getTime() + 21 * DAY), lt: new Date(u.createdAt.getTime() + 28 * DAY) } }, select: { id: true } });
      if (hit) retained++;
    }

    const forms = await prisma.usageEvent.findMany({ where: { ...where, eventType: "form_saved" }, select: { domain: true, meta: true } });
    const durations: Record<string, number[]> = {};
    for (const f of forms) {
      const m = f.meta as { via?: string; durationMs?: number };
      if (typeof m.durationMs !== "number") continue;
      (durations[`${f.domain ?? "other"}:${m.via ?? "form"}`] ??= []).push(m.durationMs);
    }
    const [records, quick, contextViews, activeDaysRows] = await Promise.all([
      prisma.usageEvent.count({ where: { ...where, eventType: "record_created" } }),
      prisma.usageEvent.count({ where: { ...where, eventType: "quick_repeat_used" } }),
      users.length ? prisma.$queryRaw<{ n: bigint }[]>`SELECT count(DISTINCT (user_id, date_trunc('day', occurred_at AT TIME ZONE 'Asia/Jakarta'))) AS n FROM usage_events WHERE user_id = ANY(${users}::uuid[]) AND event_type = 'context_viewed' AND occurred_at >= ${range.from} AND occurred_at < ${range.to}` : Promise.resolve([{ n: 0n }]),
      users.length ? prisma.$queryRaw<{ n: bigint }[]>`SELECT count(DISTINCT (user_id, date_trunc('day', occurred_at AT TIME ZONE 'Asia/Jakarta'))) AS n FROM usage_events WHERE user_id = ANY(${users}::uuid[]) AND occurred_at >= ${range.from} AND occurred_at < ${range.to}` : Promise.resolve([{ n: 0n }]),
    ]);

    const meals = users.length
      ? await prisma.$queryRaw<{ total: bigint; paired: bigint }[]>`SELECT count(*) AS total, count(*) FILTER (WHERE EXISTS (SELECT 1 FROM glucose_observations g WHERE g.user_id = m.user_id AND g.archived_at IS NULL AND g.quality_status IN ('user_reported','device_reported') AND g.measured_at BETWEEN m.consumed_at - interval '90 minutes' AND m.consumed_at + interval '10 minutes') AND EXISTS (SELECT 1 FROM glucose_observations g WHERE g.user_id = m.user_id AND g.archived_at IS NULL AND g.quality_status IN ('user_reported','device_reported') AND g.measured_at BETWEEN m.consumed_at + interval '60 minutes' AND m.consumed_at + interval '180 minutes')) AS paired FROM meal_logs m WHERE m.user_id = ANY(${users}::uuid[]) AND m.archived_at IS NULL AND m.consumed_at >= ${range.from} AND m.consumed_at < ${range.to}`
      : [{ total: 0n, paired: 0n }];
    const withHba1c = (await prisma.labResult.findMany({ where: { userId: { in: users }, test: "hba1c", archivedAt: null }, distinct: ["userId"], select: { userId: true } })).length;

    const strategyPlans = await prisma.coachingAction.findMany({ where: { userId: { in: users }, source: "PROBLEM_SOLVING", createdAt: { gte: range.from, lt: range.to } }, include: { outcomes: true } });
    const adjustments = await prisma.auditEvent.findMany({ where: { userId: { in: users }, eventType: "goal_updated", occurredAt: { gte: range.from, lt: range.to } }, select: { metadata: true } });
    const dir = (d: string) => adjustments.filter((a) => (a.metadata as { source?: string; direction?: string } | null)?.source === "weekly_reflection" && (a.metadata as { direction?: string }).direction === d).length;
    const userWeeks = (users.length * days) / 7;
    const reports = await prisma.incidentReport.count({ where: { userId: { in: users }, createdAt: { gte: range.from, lt: range.to } } });
    const flagChanges = await prisma.auditEvent.count({ where: { eventType: "feature_flag_changed", occurredAt: { gte: range.from, lt: range.to } } });
    const [educationOpened, voiceUses, guestMigrations, companionUsers] = await Promise.all([
      prisma.usageEvent.count({ where: { ...where, eventType: "education_opened" } }),
      prisma.usageEvent.count({ where: { ...where, eventType: "voice_input_used" } }),
      prisma.usageEvent.count({ where: { ...where, eventType: "guest_records_migrated" } }),
      prisma.companionLink.findMany({ where: { userId: { in: users }, revokedAt: null, expiresAt: { gt: range.to }, createdAt: { lt: range.to } }, distinct: ["userId"], select: { userId: true } }),
    ]);
    const firstRecord = users.length
      ? await prisma.$queryRaw<{ minutes: number | null }[]>`SELECT EXTRACT(EPOCH FROM (min(e.occurred_at) - u."createdAt")) / 60 AS minutes FROM users u JOIN usage_events e ON e.user_id = u.id AND e.event_type = 'record_created' WHERE u.id = ANY(${users}::uuid[]) AND u."createdAt" >= ${range.from} AND u."createdAt" < ${range.to} GROUP BY u.id, u."createdAt"`
      : [];
    const safetyReplies = await prisma.conversationMessage.findMany({ where: { userId: { in: users }, role: "ASSISTANT", route: "SAFETY", createdAt: { gte: range.from, lt: range.to } }, select: { parts: true } });
    const linked = safetyReplies.filter((m) => Array.isArray(m.parts) && (m.parts as { type?: string }[]).some((p) => p.type === "education")).length;
    const [usageRows, auditRows, agentEventRows, notificationRows] = await Promise.all([prisma.usageEvent.count(), prisma.auditEvent.count(), prisma.agentRunEvent.count(), prisma.notification.count()]);

    return {
      version: MEASURES_VERSION,
      range: { from: range.from.toISOString(), to: range.to.toISOString(), days },
      cohort: { users: users.length, basis: "pengguna dengan consent product_analytics aktif" },
      engagement: { dau: round(dau, 2), wau, recordDaysPerWeekMedian: round(median(perWeek), 2), week4Retention: { eligible: created.length, retained, rate: ratio(retained, created.length) } },
      quickRecord: { recordsCreated: records, quickRepeats: quick, quickShare: ratio(quick, records), medianSaveMsByDomainVia: Object.fromEntries(Object.entries(durations).map(([k, v]) => [k, { n: v.length, medianMs: median(v) }])) },
      feedbackAtSave: { userDaysWithContextView: Number(contextViews[0]!.n), activeUserDays: Number(activeDaysRows[0]!.n), share: ratio(Number(contextViews[0]!.n), Number(activeDaysRows[0]!.n)) },
      mealGlucosePairs: { meals: Number(meals[0]!.total), paired: Number(meals[0]!.paired), share: ratio(Number(meals[0]!.paired), Number(meals[0]!.total)) },
      clinicalAnchors: { usersWithHba1c: withHba1c, share: ratio(withHba1c, users.length) },
      adaptiveGoals: { raisedWithConsent: dir("UP"), loweredWithConsent: dir("DOWN") },
      problemSolving: { plans: strategyPlans.length, withConfirmedDay: strategyPlans.filter((p) => p.outcomes.some((o) => o.status === "USER_CONFIRMED")).length },
      safetyReports: { reports, per100UserWeeks: userWeeks ? round((reports / userWeeks) * 100, 2) : null },
      ecosystem: {
        educationOpened,
        safetyRepliesWithModule: { replies: safetyReplies.length, linked, share: ratio(linked, safetyReplies.length) },
        voiceInputUses: voiceUses,
        guestMigrations,
        firstRecordWithin5Min: { newUsers: firstRecord.length, within: firstRecord.filter((r) => r.minutes !== null && Number(r.minutes) <= 5).length, share: ratio(firstRecord.filter((r) => r.minutes !== null && Number(r.minutes) <= 5).length, firstRecord.length) },
        usersWithActiveCompanion: companionUsers.length,
      },
      operations: { featureFlagChanges: flagChanges, tableRows: { usage_events: usageRows, audit_events: auditRows, agent_run_events: agentEventRows, notifications: notificationRows } },
    };
  },
};
