import { accountRoutes } from "./features/account/account.routes.ts";
import { authRoutes } from "./features/auth/auth.routes.ts";
import { consentRoutes } from "./features/consent/consent.routes.ts";
import { healthProfileRoutes } from "./features/health-profile/health-profile.routes.ts";
import { onboardingRoutes } from "./features/onboarding/onboarding.routes.ts";
import { preferencesRoutes } from "./features/preferences/preferences.routes.ts";
import { profileRoutes } from "./features/profile/profile.routes.ts";
import { todayRoutes } from "./features/today/today.routes.ts";
import { checkinsRoutes } from "./features/checkins/checkins.routes.ts";
import { nutritionRoutes } from "./features/nutrition/nutrition.routes.ts";
import { glucoseRoutes } from "./features/glucose/glucose.routes.ts";
import { timelineRoutes } from "./features/timeline/timeline.routes.ts";
import { activityRoutes } from "./features/activity/activity.routes.ts";
import { medicationRoutes } from "./features/medication/medication.routes.ts";
import { goalsRoutes } from "./features/goals/goals.routes.ts";
import { foodDiscoveryRoutes } from "./features/food-discovery/food-discovery.routes.ts";
import { foodVisionRoutes } from "./features/food-vision/food-vision.routes.ts";
import { foodPreferencesRoutes } from "./features/food-preferences/food-preferences.routes.ts";
import { remindersRoutes } from "./features/reminders/reminders.routes.ts";
import { exportRoutes } from "./features/export/export.routes.ts";
import { pushRoutes } from "./features/push/push.routes.ts";
import { agentRoutes } from "./features/agent/agent.routes.ts";
import { communityRoutes } from "./features/community/community.routes.ts";
import { mlRoutes } from "./features/ml/ml.routes.ts";
import { interventionRoutes } from "./features/interventions/intervention.routes.ts";
import { coachingRoutes } from "./features/coaching/coaching.routes.ts";
import { syncRoutes } from "./features/sync/sync.routes.ts";
import { insightsRoutes } from "./features/insights/insights.routes.ts";
import { conversationRoutes } from "./features/conversation/conversation.routes.ts";
import { mealDraftRoutes } from "./features/meal-drafts/meal-draft.routes.ts";
import { memoryRoutes } from "./features/memory/memory.routes.ts";
import { notificationRoutes, realtimeUpgrade } from "./features/notifications/notification.routes.ts";
import { featureFlagRoutes } from "./features/feature-flags/feature-flags.routes.ts";
import { gated } from "./features/feature-flags/feature-flags.service.ts";
import { usageRoutes } from "./features/usage/usage.routes.ts";
import { clinicalRoutes } from "./features/clinical/clinical.routes.ts";
import { reportRoutes } from "./features/reports/report.routes.ts";
import { quickRecordRoutes } from "./features/quick-record/quick-record.routes.ts";
import { recordContextRoutes } from "./features/record-context/record-context.routes.ts";
import { metricsRoutes } from "./infrastructure/observability/metrics.routes.ts";
import { deviceImportRoutes } from "./features/devices/device-import.routes.ts";
import { shareRoutes } from "./features/share/share.routes.ts";
import { educationRoutes } from "./features/education/education.routes.ts";
import { companionRoutes } from "./features/companion/companion.routes.ts";
import { cgmRoutes } from "./features/cgm/cgm.routes.ts";
import { jobRoutes } from "./features/jobs/jobs.routes.ts";
import { checkDatabase } from "./infrastructure/database/prisma.ts";
import { route } from "./shared/http/handler.ts";

export const appRoutes = {
  ...authRoutes,
  ...accountRoutes,
  ...consentRoutes,
  ...onboardingRoutes,
  ...profileRoutes,
  ...healthProfileRoutes,
  ...preferencesRoutes,
  ...todayRoutes,
  ...checkinsRoutes,
  ...foodDiscoveryRoutes,
  ...gated("food_vision", foodVisionRoutes),
  ...foodPreferencesRoutes,
  ...remindersRoutes,
  ...exportRoutes,
  ...pushRoutes,
  ...gated("assistant", agentRoutes),
  ...gated("conversation", conversationRoutes),
  ...mealDraftRoutes,
  ...memoryRoutes,
  ...gated("community", communityRoutes),
  ...gated("ml_inference", mlRoutes),
  ...interventionRoutes,
  ...gated("coaching", coachingRoutes),
  ...nutritionRoutes,
  ...glucoseRoutes,
  ...activityRoutes,
  ...medicationRoutes,
  ...goalsRoutes,
  ...timelineRoutes,
  ...syncRoutes,
  ...insightsRoutes,
  ...notificationRoutes,
  ...featureFlagRoutes,
  ...usageRoutes,
  ...clinicalRoutes,
  ...reportRoutes,
  ...quickRecordRoutes,
  ...recordContextRoutes,
  ...deviceImportRoutes,
  ...shareRoutes,
  ...educationRoutes,
  ...gated("companion", companionRoutes),
  ...gated("cgm", cgmRoutes),
  ...jobRoutes,
  ...metricsRoutes,
  "/api/me/realtime": realtimeUpgrade,
  "/health": route(async () => {
    const db = await checkDatabase();
    return { status: db ? 200 : 503, body: { status: db ? "ok" : "degraded", db } };
  }),
};
