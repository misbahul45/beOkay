import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { interventionService } from "./intervention.service.ts";
import { evaluateSchema, preferencesSchema, responseSchema } from "./intervention.schema.ts";

const seg = (req: Request, i: number) => z.uuid().parse(new URL(req.url).pathname.split("/")[i]);

export const interventionRoutes = {
  "/api/me/interventions/evaluate": { POST: authenticated(async ({ req, session }) => ({ body: await interventionService.evaluate(session.userId, await readJson(req, evaluateSchema)) })) },
  "/api/me/interventions": { GET: authenticated(async ({ session }) => ({ body: await interventionService.listOpen(session.userId) })) },
  "/api/me/interventions/:id/response": { POST: authenticated(async ({ req, session }) => ({ body: await interventionService.respond(session.userId, seg(req, 4), await readJson(req, responseSchema)) })) },
  "/api/me/intervention-preferences": {
    GET: authenticated(async ({ session }) => ({ body: await interventionService.getPreferences(session.userId) })),
    PATCH: authenticated(async ({ req, session }) => ({ body: await interventionService.updatePreferences(session.userId, await readJson(req, preferencesSchema)) })),
  },
};
