import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { patchOnboardingSchema } from "./onboarding.schema.ts";
import { onboardingService } from "./onboarding.service.ts";

export const onboardingRoutes = {
  "/api/me/onboarding": {
    GET: authenticated(async ({ session }) => ({ body: await onboardingService.get(session.userId) })),
    PATCH: authenticated(async ({ req, session }) => {
      const input = await readJson(req, patchOnboardingSchema);
      return { body: await onboardingService.patch(session.userId, input) };
    }),
  },
  "/api/me/onboarding/complete": {
    POST: authenticated(async ({ session }) => ({ body: await onboardingService.complete(session.userId) })),
  },
};
