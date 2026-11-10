import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import {
  activityCreateSchema,
  activityPatchSchema,
  activityQuerySchema,
} from "./activity.schema.ts";
import { activityService } from "./activity.service.ts";
import { importRequestSchema } from "./activity-import.model.ts";
import { activityImportService } from "./activity-import.service.ts";
const id = (req: Request) =>
  z.uuid().parse(new URL(req.url).pathname.split("/")[4]);
const date = (req: Request) =>
  z.iso
    .date()
    .optional()
    .parse(new URL(req.url).searchParams.get("date") ?? undefined);
export const activityRoutes = {
  "/api/me/activities": {
    GET: authenticated(async ({ req, session }) => ({
      body: await activityService.list(
        session.userId,
        activityQuerySchema.parse(
          Object.fromEntries(new URL(req.url).searchParams),
        ),
      ),
    })),
    POST: authenticated(async ({ req, session }) => ({
      status: 201,
      body: await activityService.create(
        session.userId,
        await readJson(req, activityCreateSchema),
      ),
    })),
  },
  "/api/me/activities/import": {
    POST: authenticated(async ({ req, session }) => {
      const input = await readJson(req, importRequestSchema);
      return { body: await activityImportService.import(session.userId, input.source, input.sessions) };
    }),
  },
  "/api/me/activities/summary": {
    GET: authenticated(async ({ req, session }) => ({
      body: await activityService.daily(session.userId, date(req)),
    })),
  },
  "/api/me/activities/weekly": {
    GET: authenticated(async ({ req, session }) => ({
      body: await activityService.weekly(session.userId, date(req)),
    })),
  },
  "/api/me/activities/:id": {
    GET: authenticated(async ({ req, session }) => ({
      body: await activityService.get(session.userId, id(req)),
    })),
    PATCH: authenticated(async ({ req, session }) => ({
      body: await activityService.update(
        session.userId,
        id(req),
        await readJson(req, activityPatchSchema),
      ),
    })),
  },
  "/api/me/activities/:id/revisions": {
    GET: authenticated(async ({ req, session }) => ({
      body: await activityService.revisions(session.userId, id(req)),
    })),
  },
};
