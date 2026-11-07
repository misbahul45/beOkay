import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { updatePreferencesSchema } from "./preferences.schema.ts";
import { preferencesService } from "./preferences.service.ts";

export const preferencesRoutes = {
  "/api/me/preferences": {
    GET: authenticated(async ({ session }) => ({ body: await preferencesService.get(session.userId) })),
    PATCH: authenticated(async ({ req, session }) => {
      const input = await readJson(req, updatePreferencesSchema);
      return { body: await preferencesService.update(session.userId, input) };
    }),
  },
};
