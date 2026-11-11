import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { draftConfirmSchema } from "./meal-draft.schema.ts";
import { mealDraftService } from "./meal-draft.service.ts";

const seg = (req: Request, i: number) => z.uuid().parse(new URL(req.url).pathname.split("/")[i]);

export const mealDraftRoutes = {
  "/api/me/meal-drafts/:id": {
    GET: authenticated(async ({ req, session }) => ({ body: await mealDraftService.get(session.userId, seg(req, 4)) })),
  },
  "/api/me/meal-drafts/:id/confirm": {
    POST: authenticated(async ({ req, session }) => {
      const result = await mealDraftService.confirm(session.userId, seg(req, 4), await readJson(req, draftConfirmSchema));
      return { status: result.replayed ? 200 : 201, body: result };
    }),
  },
  "/api/me/meal-drafts/:id/items/:index/web-search": {
    POST: authenticated(async ({ req, session }) => {
      const index = z.coerce.number().int().min(0).max(29).parse(new URL(req.url).pathname.split("/")[6]);
      return { body: await mealDraftService.webLookup(session.userId, seg(req, 4), index) };
    }),
  },
  "/api/me/meal-drafts/:id/discard": {
    POST: authenticated(async ({ req, session }) => ({ body: await mealDraftService.discard(session.userId, seg(req, 4)) })),
  },
};
