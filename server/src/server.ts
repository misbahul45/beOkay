import { env } from "./config/env.ts";
import { createFcmClient } from "./features/push/fcm.client.ts";
import { startPushDispatcher } from "./features/push/push-dispatcher.ts";
import { startAgentWorker } from "./features/agent/agent-worker.ts";
import { canSubscribeTopic } from "./features/community/community.service.ts";
import { startChallengeLifecycle } from "./features/community/lifecycle.service.ts";
import { coachingService } from "./features/coaching/coaching.service.ts";
import { notificationService, startNotificationWorker } from "./features/notifications/notification.service.ts";
import { clinicalService } from "./features/clinical/clinical.service.ts";
import { startRetentionWorker } from "./features/retention/retention.service.ts";
import { featureFlags } from "./features/feature-flags/feature-flags.service.ts";
import { educationService } from "./features/education/education.service.ts";
import { prisma } from "./infrastructure/database/prisma.ts";
import { realtime, websocket, type SocketData } from "./infrastructure/realtime/realtime.ts";
import { route } from "./shared/http/handler.ts";
import { logEvent } from "./shared/http/logger.ts";
import { appRoutes } from "./routes.ts";

const server = Bun.serve<SocketData>({
  websocket,
  port: env.PORT,
  idleTimeout: 60, // SSE: peristiwa/detak jantung lebih jarang dari 60 dtk
  routes: appRoutes,
  fetch: route(async () => ({ status: 404, body: { error: { code: "NOT_FOUND", message: "Rute tidak ditemukan." } } })),
});

realtime.attach(server);
if (env.REALTIME_REDIS_URL) {
  realtime.connectBus(env.REALTIME_REDIS_URL).then(
    () => logEvent("info", "realtime_bus_connected"),
    (e) => logEvent("error", "realtime_bus_failed", { name: e instanceof Error ? e.name : "unknown" }),
  );
}
realtime.setTopicGuard(canSubscribeTopic);
realtime.onOpen = async (ws) => {
  ws.send(JSON.stringify({ type: "hello", ...(await notificationService.unreadCount(ws.data.userId)) }));
};

const fcm = createFcmClient({ projectId: env.FCM_PROJECT_ID, serviceAccountJson: env.FCM_SERVICE_ACCOUNT_JSON });
notificationService.setPushSender(fcm);
const dispatcher = env.PUSH_DISPATCH_ENABLED ? startPushDispatcher(fcm) : { stop() {} };
logEvent("info", "push_status", { fcmConfigured: fcm.configured, dispatcher: env.PUSH_DISPATCH_ENABLED && fcm.configured });

const agentWorker = env.OUTBOX_WORKER_ENABLED ? startAgentWorker() : { stop() {} };
let lastNudge = 0;
const notifyWorker = env.NOTIFY_WORKER_ENABLED
  ? startNotificationWorker(30_000, async () => {
      if (Date.now() - lastNudge < 60 * 60_000) return;
      lastNudge = Date.now();
      if (await featureFlags.isEnabled("coaching")) await coachingService.nudgeReflections();
      await clinicalService.remindDueLabs();
    })
  : { stop() {} };
const retention = env.RETENTION_WORKER_ENABLED ? startRetentionWorker() : { stop() {} };
const lifecycle = env.CHALLENGE_LIFECYCLE_ENABLED ? startChallengeLifecycle() : { stop() {} };
logEvent("info", "server_started", { port: server.port, env: env.NODE_ENV });
educationService.sync().then((r) => logEvent("info", "education_synced", { created: r.created, updated: r.updated, unchanged: r.unchanged, rejected: r.rejected.length }), (e) => logEvent("error", "education_sync_failed", { message: e instanceof Error ? e.message : String(e) }));

async function shutdown() {
  dispatcher.stop();
  agentWorker.stop();
  notifyWorker.stop();
  lifecycle.stop();
  retention.stop();
  await server.stop();
  await prisma.$disconnect();
  process.exit(0);
}
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
