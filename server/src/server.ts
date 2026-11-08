import { env } from "./config/env.ts";
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
import { insightsRoutes } from "./features/insights/insights.routes.ts";
import { checkDatabase, prisma } from "./infrastructure/database/prisma.ts";
import { route } from "./shared/http/handler.ts";
import { logEvent } from "./shared/http/logger.ts";

const server = Bun.serve({
  port: env.PORT,
  routes: {
    ...authRoutes,
    ...consentRoutes,
    ...onboardingRoutes,
    ...profileRoutes,
    ...healthProfileRoutes,
    ...preferencesRoutes,
    ...todayRoutes,
    ...nutritionRoutes,
    ...glucoseRoutes,
    ...timelineRoutes,
    ...insightsRoutes,
    "/health": route(async () => {
      const db = await checkDatabase();
      return { status: db ? 200 : 503, body: { status: db ? "ok" : "degraded", db } };
    }),
  },
  fetch: route(async () => ({ status: 404, body: { error: { code: "NOT_FOUND", message: "Rute tidak ditemukan." } } })),
});

logEvent("info", "server_started", { port: server.port, env: env.NODE_ENV });

async function shutdown() {
  await server.stop();
  await prisma.$disconnect();
  process.exit(0);
}
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
