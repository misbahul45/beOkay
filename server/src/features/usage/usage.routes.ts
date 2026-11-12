import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { clientBatchSchema } from "./usage.model.ts";
import { usageService } from "./usage.service.ts";

export const usageRoutes = {
  "/api/me/usage-events": {
    GET: authenticated(async ({ session }) => ({ body: await usageService.mine(session.userId) })),
    POST: authenticated(async ({ req, session }) => ({ status: 202, body: await usageService.ingest(session.userId, await readJson(req, clientBatchSchema)) })),
    DELETE: authenticated(async ({ session }) => ({ body: await usageService.forget(session.userId) })),
  },
};
