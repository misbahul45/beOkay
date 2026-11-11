import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { AppError } from "../../shared/errors/app-error.ts";

export const EXPORT_FORMAT_VERSION = "beokay-export-v2";
const WINDOW_MS = 60 * 60_000;
const MAX_EXPORTS = 5;
const calls = new Map<string, number[]>();

export const EXPORTED_TABLES = [
  "user_profiles",
  "health_profiles",
  "user_settings",
  "onboarding_progress",
  "consent_records",
  "food_catalog",
  "food_portion_measures",
  "meal_logs",
  "glucose_observations",
  "activity_sessions",
  "medication_regimens",
  "medication_schedules",
  "medication_intakes",
  "behavior_goals",
  "goal_checkins",
  "record_revisions",
  "food_preferences",
  "reminders",
  "push_devices",
  "push_deliveries",
  "agent_runs",
  "recommendations",
  "recommendation_decisions",
  "recommendation_feedback",
  "recommendation_outcomes",
  "planned_meals",
  "activity_plans",
  "personalization_profiles",
  "personalization_events",
  "community_memberships",
  "challenge_participants",
  "challenge_checkins",
  "score_events",
  "intervention_preferences",
  "intervention_decisions",
  "ml_inference_runs",
  "conversation_threads",
  "conversation_messages",
  "meal_drafts",
  "memory_items",
  "audit_events",
] as const;

export const EXCLUDED_TABLES: Record<string, string> = {
  sessions: "Sesi login adalah data keamanan, bukan data pribadimu.",
  accounts: "Berisi hash kata sandi.",
  outbox_events: "Antrean pemrosesan internal.",
  summary_projections: "Ringkasan turunan yang dihitung ulang dari catatanmu.",
  sync_operations: "Kuitansi teknis sinkronisasi; isinya sudah ada di catatan yang diekspor.",
};

const INTERNAL_KEYS = new Set(["createHash", "payloadHash", "idempotencyKey", "dedupeKey", "argsHash", "aliasKey", "providerMessageId", "token"]);
export function stripInternal<T>(value: T): T {
  if (Array.isArray(value)) return value.map(stripInternal) as T;
  if (value && typeof value === "object" && !(value instanceof Date) && !("toFixed" in (value as object))) {
    return Object.fromEntries(Object.entries(value as object).filter(([k]) => !INTERNAL_KEYS.has(k)).map(([k, v]) => [k, stripInternal(v)])) as T;
  }
  return value;
}

export const exportService = {
  async build(userId: string, now = new Date()) {
    const t = now.getTime();
    const recent = (calls.get(userId) ?? []).filter((x) => t - x < WINDOW_MS);
    if (recent.length >= MAX_EXPORTS) {
      calls.set(userId, recent);
      throw new AppError(429, "EXPORT_RATE_LIMITED", "Terlalu sering mengunduh data. Coba lagi dalam satu jam.");
    }
    calls.set(userId, [...recent, t]);

    const own = { userId };
    const asc = { createdAt: "asc" as const };
    const [
      user, profile, healthProfile, settings, onboarding, consents, foods, portionMeasures, meals, glucose, activities, regimens, goals, revisions,
      foodPreferences, reminders, pushDevices, pushDeliveries, agentRuns, recommendations, plannedMeals, activityPlans, personalization,
      personalizationEvents, communityMemberships, challengeParticipants, challengeCheckins, scoreEvents, interventionPreference, interventionDecisions,
      mlInferenceRuns, conversationThreads, mealDrafts, memoryItems, audit,
    ] = await prisma.$transaction(
      [
        prisma.users.findUniqueOrThrow({ where: { id: userId }, select: { id: true, name: true, email: true, emailVerified: true, createdAt: true } }),
        prisma.userProfile.findUnique({ where: own }),
        prisma.healthProfile.findUnique({ where: own }),
        prisma.userSettings.findUnique({ where: own }),
        prisma.onboardingProgress.findUnique({ where: own }),
        prisma.consentRecord.findMany({ where: own, orderBy: { grantedAt: "asc" } }),
        prisma.foodCatalog.findMany({ where: own, orderBy: asc }),
        prisma.foodPortionMeasure.findMany({ where: own, orderBy: asc }),
        prisma.mealLog.findMany({ where: own, include: { items: true }, orderBy: { consumedAt: "asc" } }),
        prisma.glucoseObservation.findMany({ where: own, orderBy: { measuredAt: "asc" } }),
        prisma.activitySession.findMany({ where: own, orderBy: { startedAt: "asc" } }),
        prisma.medicationRegimen.findMany({ where: own, include: { schedules: true, intakes: true }, orderBy: asc }),
        prisma.behaviorGoal.findMany({ where: own, include: { checkins: true }, orderBy: asc }),
        prisma.recordRevision.findMany({ where: own, orderBy: asc }),
        prisma.foodPreference.findMany({ where: own, orderBy: asc }),
        prisma.reminder.findMany({ where: own, orderBy: asc }),
        prisma.pushDevice.findMany({ where: own, select: { id: true, platform: true, appVersion: true, active: true, createdAt: true, lastSeenAt: true }, orderBy: asc }),
        prisma.pushDelivery.findMany({ where: own, select: { id: true, reminderId: true, scheduledAt: true, status: true, attemptedAt: true }, orderBy: { attemptedAt: "asc" } }),
        prisma.agentRun.findMany({ where: own, select: { id: true, status: true, intent: true, inputText: true, state: true, safetyDecision: true, parentRunId: true, turn: true, createdAt: true }, orderBy: asc }),
        prisma.recommendation.findMany({ where: own, include: { decisions: true, feedback: true, outcome: true }, orderBy: asc }),
        prisma.plannedMeal.findMany({ where: own, orderBy: asc }),
        prisma.activityPlan.findMany({ where: own, orderBy: asc }),
        prisma.personalizationProfile.findUnique({ where: own }),
        prisma.personalizationEvent.findMany({ where: own, orderBy: asc }),
        prisma.communityMembership.findMany({ where: own, include: { community: { select: { name: true, regionCode: true } } }, orderBy: { joinedAt: "asc" } }),
        prisma.challengeParticipant.findMany({ where: own, include: { challenge: { select: { title: true, startsOn: true, endsOn: true } } }, orderBy: { joinedAt: "asc" } }),
        prisma.challengeCheckin.findMany({ where: own, orderBy: asc }),
        prisma.scoreEvent.findMany({ where: own, orderBy: asc }),
        prisma.interventionPreference.findUnique({ where: own }),
        prisma.interventionDecision.findMany({ where: own, orderBy: { decidedAt: "asc" } }),
        prisma.mlInferenceRun.findMany({ where: own, select: { id: true, mode: true, status: true, topLabel: true, topProbability: true, createdAt: true }, orderBy: asc }),
        prisma.conversationThread.findMany({
          where: own,
          select: { id: true, title: true, messageCount: true, lastMessageAt: true, createdAt: true, messages: { select: { id: true, seq: true, role: true, text: true, parts: true, route: true, routerVersion: true, basis: true, runId: true, replyToId: true, createdAt: true }, orderBy: { seq: "asc" } } },
          orderBy: asc,
        }),
        prisma.mealDraft.findMany({ where: own, orderBy: asc }),
        prisma.memoryItem.findMany({ where: own, orderBy: asc }),
        prisma.auditEvent.findMany({ where: own, orderBy: { occurredAt: "asc" } }),
      ],
      { isolationLevel: "RepeatableRead" },
    );

    const data = stripInternal({
      account: user,
      profile,
      healthProfile,
      settings,
      onboarding,
      consents,
      foods,
      foodPortionMeasures: portionMeasures,
      meals,
      glucoseObservations: glucose,
      activitySessions: activities,
      medicationRegimens: regimens,
      goals,
      recordRevisions: revisions,
      foodPreferences,
      reminders,
      pushDevices,
      pushDeliveries,
      assistantRuns: agentRuns,
      recommendations,
      plannedMeals,
      activityPlans,
      personalization,
      personalizationEvents,
      communityMemberships,
      challengeParticipants,
      challengeCheckins,
      scoreEvents,
      interventionPreference,
      interventionDecisions,
      modelInferenceRuns: mlInferenceRuns,
      conversations: conversationThreads,
      mealDrafts,
      memories: memoryItems,
      auditEvents: audit,
    });
    const counts = Object.fromEntries(Object.entries(data).map(([k, v]) => [k, Array.isArray(v) ? v.length : v ? 1 : 0]));
    await recordAudit(prisma, { userId, eventType: "export_requested", metadata: { format: EXPORT_FORMAT_VERSION } });
    return {
      format: EXPORT_FORMAT_VERSION,
      generatedAt: now.toISOString(),
      notice: "Berkas ini berisi data kesehatanmu. Simpan di tempat yang aman.",
      excluded: EXCLUDED_TABLES,
      counts,
      data,
    };
  },
};
