import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { reminderCreateSchema, reminderPatchSchema, reminderUpcomingQuerySchema } from "./reminders.schema.ts";
import { remindersService } from "./reminders.service.ts";

export const remindersRoutes = {
  "/api/me/reminders": {
    GET: authenticated(async ({ session }) => ({ body: await remindersService.list(session.userId) })),
    POST: authenticated(async ({ req, session }) => ({ status: 201, body: await remindersService.create(session.userId, await readJson(req, reminderCreateSchema)) })),
  },
  "/api/me/reminders/upcoming": {
    GET: authenticated(async ({ req, session }) => ({
      body: await remindersService.upcoming(session.userId, reminderUpcomingQuerySchema.parse(Object.fromEntries(new URL(req.url).searchParams)).days),
    })),
  },
  "/api/me/reminders/:id": {
    PATCH: authenticated(async ({ req, session }) => ({
      body: await remindersService.update(session.userId, z.uuid().parse(new URL(req.url).pathname.split("/")[4]), await readJson(req, reminderPatchSchema)),
    })),
  },
};
