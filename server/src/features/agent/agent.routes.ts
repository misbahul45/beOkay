import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { consentService } from "../consent/consent.service.ts";
import { agentService } from "./agent.service.ts";
import { decisionSchema, feedbackSchema, runCreateSchema } from "./agent.schema.ts";
import { personalization } from "./personalization.ts";
import { streamRun } from "./agent.stream.ts";
import { TOOL_CONTRACTS } from "./agent.tools.ts";

const seg = (req: Request, i: number) => z.uuid().parse(new URL(req.url).pathname.split("/")[i]);

export const agentRoutes = {
  "/api/me/agent/runs": {
    // ?async=1: balas 202 segera dan jalankan di latar; ikuti lewat /runs/:id/stream.
    POST: authenticated(async ({ req, session }) => {
      const background = new URL(req.url).searchParams.get("async") === "1";
      return { status: background ? 202 : 201, body: await agentService.createRun(session.userId, await readJson(req, runCreateSchema), { background }) };
    }),
  },
  "/api/me/agent/runs/:id/stream": {
    GET: authenticated(async ({ req, session }) => {
      const u = new URL(req.url);
      const after = Number(req.headers.get("last-event-id") ?? u.searchParams.get("after") ?? 0);
      return streamRun(session.userId, seg(req, 5), Number.isInteger(after) && after >= 0 ? after : 0, req.signal);
    }),
  },
  "/api/me/agent/pending": { GET: authenticated(async ({ session }) => ({ body: await agentService.listPending(session.userId) })) },
  "/api/me/agent/runs/:id": { GET: authenticated(async ({ req, session }) => ({ body: await agentService.getRun(session.userId, seg(req, 5)) })) },
  "/api/me/agent/runs/:id/cancel": { POST: authenticated(async ({ req, session }) => ({ body: await agentService.cancelRun(session.userId, seg(req, 5)) })) },
  "/api/me/agent/recommendations/:id/decision": {
    POST: authenticated(async ({ req, session }) => ({ body: await agentService.decide(session.userId, seg(req, 5), await readJson(req, decisionSchema)) })),
  },
  "/api/me/agent/recommendations/:id/feedback": {
    POST: authenticated(async ({ req, session }) => ({ body: await agentService.feedback(session.userId, seg(req, 5), await readJson(req, feedbackSchema)) })),
  },
  "/api/me/agent/tools": { GET: authenticated(async () => ({ body: { items: TOOL_CONTRACTS } })) },
  "/api/me/activity-plans": { GET: authenticated(async ({ session }) => ({ body: await agentService.listActivityPlans(session.userId) })) },
  "/api/me/planned-meals": { GET: authenticated(async ({ session }) => ({ body: await agentService.listPlannedMeals(session.userId) })) },
  "/api/me/personalization": {
    GET: authenticated(async ({ session }) => {
      await consentService.requireConsent(session.userId, "personalized_ai");
      return { body: await personalization.summary(session.userId) };
    }),
    DELETE: authenticated(async ({ session }) => ({ body: await personalization.reset(session.userId) })),
  },
};
