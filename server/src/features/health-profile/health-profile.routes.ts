import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { patchHealthProfileSchema, putHealthProfileSchema } from "./health-profile.schema.ts";
import { healthProfileService } from "./health-profile.service.ts";

export const healthProfileRoutes = {
  "/api/me/health-profile": {
    GET: authenticated(async ({ session }) => ({ body: await healthProfileService.get(session.userId) })),
    PUT: authenticated(async ({ req, session }) => {
      const input = await readJson(req, putHealthProfileSchema);
      return { body: await healthProfileService.put(session.userId, input) };
    }),
    PATCH: authenticated(async ({ req, session }) => {
      const input = await readJson(req, patchHealthProfileSchema);
      return { body: await healthProfileService.patch(session.userId, input) };
    }),
  },
};
