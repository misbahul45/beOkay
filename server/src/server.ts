import { env } from "./config/env.ts";
import { accountRoutes } from "./features/account/account.routes.ts";
import { authRoutes } from "./features/auth/auth.routes.ts";
import { consentRoutes } from "./features/consent/consent.routes.ts";
import { healthProfileRoutes } from "./features/health-profile/health-profile.routes.ts";
import { onboardingRoutes } from "./features/onboarding/onboarding.routes.ts";
import { preferencesRoutes } from "./features/preferences/preferences.routes.ts";
import { profileRoutes } from "./features/profile/profile.routes.ts";
import { todayRoutes } from "./features/today/today.routes.ts";
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
import { createFcmClient } from "./features/push/fcm.client.ts";
import { startPushDispatcher } from "./features/push/push-dispatcher.ts";
import { startAgentWorker } from "./features/agent/agent-worker.ts";
import { agentRoutes } from "./features/agent/agent.routes.ts";
import { communityRoutes } from "./features/community/community.routes.ts";
import { mlRoutes } from "./features/ml/ml.routes.ts";
import { interventionRoutes } from "./features/interventions/intervention.routes.ts";
import { syncRoutes } from "./features/sync/sync.routes.ts";
import { insightsRoutes } from "./features/insights/insights.routes.ts";
import { conversationRoutes } from "./features/conversation/conversation.routes.ts";
import { checkDatabase, prisma } from "./infrastructure/database/prisma.ts";
import { route } from "./shared/http/handler.ts";
import { logEvent } from "./shared/http/logger.ts";

const server = Bun.serve({
  port: env.PORT,
  idleTimeout: 60, // SSE: peristiwa/detak jantung lebih jarang dari 60 dtk
  routes: {
    ...authRoutes,
    ...accountRoutes,
    ...consentRoutes,
    ...onboardingRoutes,
    ...profileRoutes,
    ...healthProfileRoutes,
    ...preferencesRoutes,
    ...todayRoutes,
    ...foodDiscoveryRoutes,
    ...foodVisionRoutes,
    ...foodPreferencesRoutes,
    ...remindersRoutes,
    ...exportRoutes,
    ...pushRoutes,
    ...agentRoutes,
    ...conversationRoutes,
    ...communityRoutes,
    ...mlRoutes,
    ...interventionRoutes,
    ...nutritionRoutes,
    ...glucoseRoutes,
    ...activityRoutes,
    ...medicationRoutes,
    ...goalsRoutes,
    ...timelineRoutes,
    ...syncRoutes,
    ...insightsRoutes,
    "/health": route(async () => {
      const db = await checkDatabase();
      return { status: db ? 200 : 503, body: { status: db ? "ok" : "degraded", db } };
    }),
  },
  fetch: route(async () => ({ status: 404, body: { error: { code: "NOT_FOUND", message: "Rute tidak ditemukan." } } })),
});

const fcm = createFcmClient({ projectId: env.FCM_PROJECT_ID, serviceAccountJson: env.FCM_SERVICE_ACCOUNT_JSON });
const dispatcher = env.PUSH_DISPATCH_ENABLED ? startPushDispatcher(fcm) : { stop() {} };
logEvent("info", "push_status", { fcmConfigured: fcm.configured, dispatcher: env.PUSH_DISPATCH_ENABLED && fcm.configured });

const agentWorker = env.OUTBOX_WORKER_ENABLED ? startAgentWorker() : { stop() {} };
logEvent("info", "server_started", { port: server.port, env: env.NODE_ENV });

async function shutdown() {
  dispatcher.stop();
  agentWorker.stop();
  await server.stop();
  await prisma.$disconnect();
  process.exit(0);
}
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
