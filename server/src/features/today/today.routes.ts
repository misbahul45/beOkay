import { authenticated } from "../auth/guard.ts";
import { cohortService } from "../cohort/cohort.service.ts";
import { nextActionService } from "./next-action.service.ts";
import { todayService } from "./today.service.ts";

export const todayRoutes = {
  "/api/me/today": {
    GET: authenticated(async ({ session }) => ({ body: await todayService.get(session.userId) })),
  },
  "/api/me/today/next-action": {
    GET: authenticated(async ({ session }) => ({ body: await nextActionService.get(session.userId) })),
  },
  "/api/me/progress/peers": {
    GET: authenticated(async ({ session }) => ({ body: await nextActionService.peers(session.userId) })),
  },
  "/api/me/journey": {
    GET: authenticated(async ({ session }) => ({ body: await cohortService.view(session.userId) })),
  },
};
