import { z } from "zod";
import { readJson } from "../../shared/http/handler.ts";
import { authenticated } from "../auth/guard.ts";
import { checkinSchema, confirmSchema, decisionSchema, feedbackSchema } from "./coaching.schema.ts";
import { coachingService } from "./coaching.service.ts";

const seg = (req: Request, i: number) => z.uuid().parse(new URL(req.url).pathname.split("/")[i]);

export const coachingRoutes = {
  "/api/me/coaching": { GET: authenticated(async ({ session }) => ({ body: await coachingService.overview(session.userId) })) },
  "/api/me/coaching/opportunities": { GET: authenticated(async ({ session }) => ({ body: await coachingService.opportunities(session.userId) })) },
  "/api/me/coaching/actions/:id/decision": { POST: authenticated(async ({ req, session }) => ({ body: await coachingService.decide(session.userId, seg(req, 5), await readJson(req, decisionSchema)) })) },
  "/api/me/coaching/actions/:id/feedback": { POST: authenticated(async ({ req, session }) => ({ body: await coachingService.feedback(session.userId, seg(req, 5), await readJson(req, feedbackSchema)) })) },
  "/api/me/coaching/actions/:id/confirm": { POST: authenticated(async ({ req, session }) => ({ body: await coachingService.confirm(session.userId, seg(req, 5), await readJson(req, confirmSchema)) })) },
  "/api/me/coaching/checkins": {
    GET: authenticated(async ({ session }) => ({ body: await coachingService.reflection(session.userId) })),
    POST: authenticated(async ({ req, session }) => ({ status: 201, body: await coachingService.submitCheckin(session.userId, await readJson(req, checkinSchema)) })),
  },
};
