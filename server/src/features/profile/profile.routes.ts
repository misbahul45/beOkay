import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { updateProfileSchema } from "./profile.schema.ts";
import { profileService } from "./profile.service.ts";

export const profileRoutes = {
  "/api/me/profile": {
    GET: authenticated(async ({ session }) => ({ body: await profileService.get(session.userId) })),
    PATCH: authenticated(async ({ req, session }) => {
      const input = await readJson(req, updateProfileSchema);
      return { body: await profileService.update(session.userId, req.headers, input) };
    }),
  },
};
