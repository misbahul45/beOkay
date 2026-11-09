import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { intakeCreateSchema, intakePatchSchema, listQuerySchema, regimenCreateSchema, regimenPatchSchema, scheduleCreateSchema, schedulePatchSchema, todayQuerySchema } from "./medication.schema.ts";
import { medicationService } from "./medication.service.ts";
const seg = (req: Request, i: number) => z.uuid().parse(new URL(req.url).pathname.split("/")[i]);
const query = (req: Request) => Object.fromEntries(new URL(req.url).searchParams);
export const medicationRoutes = {
  "/api/me/medications": {
    GET: authenticated(async ({ req, session }) => ({ body: await medicationService.list(session.userId, listQuerySchema.parse(query(req))) })),
    POST: authenticated(async ({ req, session }) => ({ status: 201, body: await medicationService.create(session.userId, await readJson(req, regimenCreateSchema)) })),
  },
  "/api/me/medications/today": {
    GET: authenticated(async ({ req, session }) => ({ body: await medicationService.today(session.userId, todayQuerySchema.parse(query(req)).date) })),
  },
  "/api/me/medications/:id": {
    GET: authenticated(async ({ req, session }) => ({ body: await medicationService.get(session.userId, seg(req, 4)) })),
    PATCH: authenticated(async ({ req, session }) => ({ body: await medicationService.update(session.userId, seg(req, 4), await readJson(req, regimenPatchSchema)) })),
  },
  "/api/me/medications/:id/revisions": {
    GET: authenticated(async ({ req, session }) => ({ body: await medicationService.revisions(session.userId, seg(req, 4)) })),
  },
  "/api/me/medications/:id/schedules": {
    GET: authenticated(async ({ req, session }) => ({ body: await medicationService.listSchedules(session.userId, seg(req, 4)) })),
    POST: authenticated(async ({ req, session }) => ({ status: 201, body: await medicationService.createSchedule(session.userId, seg(req, 4), await readJson(req, scheduleCreateSchema)) })),
  },
  "/api/me/medications/:id/schedules/:scheduleId": {
    PATCH: authenticated(async ({ req, session }) => ({ body: await medicationService.updateSchedule(session.userId, seg(req, 4), seg(req, 6), await readJson(req, schedulePatchSchema)) })),
  },
  "/api/me/medications/:id/intakes": {
    GET: authenticated(async ({ req, session }) => ({ body: await medicationService.listIntakes(session.userId, seg(req, 4), listQuerySchema.pick({ cursor: true, limit: true, archived: true }).parse(query(req))) })),
    POST: authenticated(async ({ req, session }) => ({ status: 201, body: await medicationService.createIntake(session.userId, seg(req, 4), await readJson(req, intakeCreateSchema)) })),
  },
  "/api/me/medications/:id/intakes/:intakeId": {
    GET: authenticated(async ({ req, session }) => ({ body: await medicationService.getIntake(session.userId, seg(req, 4), seg(req, 6)) })),
    PATCH: authenticated(async ({ req, session }) => ({ body: await medicationService.updateIntake(session.userId, seg(req, 4), seg(req, 6), await readJson(req, intakePatchSchema)) })),
  },
};
