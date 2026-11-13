import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { checkinsService, energySchema } from "./checkins.service.ts";

export const checkinsRoutes = {
  "/api/me/checkins/today": {
    GET: authenticated(async ({ session }) => ({ body: await checkinsService.today(session.userId) })),
  },
  "/api/me/checkins/energy": {
    PUT: authenticated(async ({ req, session }) => ({ body: await checkinsService.setEnergy(session.userId, (await readJson(req, energySchema)).energy) })),
  },
};
