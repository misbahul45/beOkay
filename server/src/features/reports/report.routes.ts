import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { reportSchema, reportService } from "./report.service.ts";

export const reportRoutes = {
  "/api/me/reports": {
    GET: authenticated(async ({ session }) => ({ body: await reportService.mine(session.userId) })),
    POST: authenticated(async ({ req, session }) => ({ status: 201, body: await reportService.submit(session.userId, session.email, await readJson(req, reportSchema)) })),
  },
};
