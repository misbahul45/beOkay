import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { syncRequestSchema } from "./sync.schema.ts";
import { syncService } from "./sync.service.ts";

export const syncRoutes = {
  "/api/me/sync/operations": {
    POST: authenticated(async ({ req, session }) => ({
      body: await syncService.apply(session.userId, (await readJson(req, syncRequestSchema)).operations),
    })),
  },
  "/api/me/sync/status": {
    GET: authenticated(async ({ session }) => ({ body: await syncService.status(session.userId) })),
  },
};
