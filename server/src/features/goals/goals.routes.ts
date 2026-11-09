import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { checkinCreateSchema, checkinPatchSchema, checkinsQuerySchema, goalCreateSchema, goalPatchSchema, goalsQuerySchema } from "./goals.schema.ts";
import { goalsService } from "./goals.service.ts";
const seg = (req: Request, i: number) => z.uuid().parse(new URL(req.url).pathname.split("/")[i]);
const query = (req: Request) => Object.fromEntries(new URL(req.url).searchParams);
export const goalsRoutes = {
  "/api/me/goals": {
    GET: authenticated(async ({ req, session }) => ({ body: await goalsService.list(session.userId, goalsQuerySchema.parse(query(req))) })),
    POST: authenticated(async ({ req, session }) => ({ status: 201, body: await goalsService.create(session.userId, await readJson(req, goalCreateSchema)) })),
  },
  "/api/me/goals/:id": {
    GET: authenticated(async ({ req, session }) => ({ body: await goalsService.get(session.userId, seg(req, 4)) })),
    PATCH: authenticated(async ({ req, session }) => ({ body: await goalsService.update(session.userId, seg(req, 4), await readJson(req, goalPatchSchema)) })),
  },
  "/api/me/goals/:id/checkins": {
    GET: authenticated(async ({ req, session }) => ({ body: await goalsService.listCheckins(session.userId, seg(req, 4), checkinsQuerySchema.parse(query(req))) })),
    POST: authenticated(async ({ req, session }) => ({ status: 201, body: await goalsService.createCheckin(session.userId, seg(req, 4), await readJson(req, checkinCreateSchema)) })),
  },
  "/api/me/goals/:id/checkins/:checkinId": {
    PATCH: authenticated(async ({ req, session }) => ({ body: await goalsService.updateCheckin(session.userId, seg(req, 4), seg(req, 6), await readJson(req, checkinPatchSchema)) })),
  },
};
