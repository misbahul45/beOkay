import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import {
  glucoseCreateSchema,
  glucosePatchSchema,
  glucoseQuerySchema,
} from "./glucose.schema.ts";
import { glucoseService } from "./glucose.service.ts";
const id = (req: Request) =>
  z.uuid().parse(new URL(req.url).pathname.split("/")[4]);
export const glucoseRoutes = {
  "/api/me/glucose": {
    GET: authenticated(async ({ req, session }) => ({
      body: await glucoseService.list(
        session.userId,
        glucoseQuerySchema.parse(
          Object.fromEntries(new URL(req.url).searchParams),
        ),
      ),
    })),
    POST: authenticated(async ({ req, session }) => ({
      status: 201,
      body: await glucoseService.create(
        session.userId,
        await readJson(req, glucoseCreateSchema),
      ),
    })),
  },
  "/api/me/glucose/summary": {
    GET: authenticated(async ({ req, session }) => ({
      body: await glucoseService.daily(
        session.userId,
        z.iso
          .date()
          .optional()
          .parse(new URL(req.url).searchParams.get("date") ?? undefined),
      ),
    })),
  },
  "/api/me/glucose/:id": {
    GET: authenticated(async ({ req, session }) => ({
      body: await glucoseService.get(session.userId, id(req)),
    })),
    PATCH: authenticated(async ({ req, session }) => ({
      body: await glucoseService.update(
        session.userId,
        id(req),
        await readJson(req, glucosePatchSchema),
      ),
    })),
  },
  "/api/me/glucose/:id/revisions": {
    GET: authenticated(async ({ req, session }) => ({
      body: await glucoseService.revisions(session.userId, id(req)),
    })),
  },
};
