import { authenticated } from "../auth/guard.ts";
import { todayService } from "./today.service.ts";

export const todayRoutes = {
  "/api/me/today": {
    GET: authenticated(async ({ session }) => ({ body: await todayService.get(session.userId) })),
  },
};
