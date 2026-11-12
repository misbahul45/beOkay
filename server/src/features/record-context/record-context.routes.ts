import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { recordContextService } from "./record-context.service.ts";

const id = (req: Request) => z.uuid().parse(new URL(req.url).pathname.split("/")[4]);

export const recordContextRoutes = {
  "/api/me/glucose/:id/context": { GET: authenticated(async ({ req, session }) => ({ body: await recordContextService.glucose(session.userId, id(req)) })) },
  "/api/me/meals/:id/context": { GET: authenticated(async ({ req, session }) => ({ body: await recordContextService.meal(session.userId, id(req)) })) },
};
