import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { deviceImportSchema, devicePreferencesSchema, syncCheckpointSchema } from "./device-import.schema.ts";
import { deviceImportService } from "./device-import.service.ts";
import { deviceQualityService } from "./quality.service.ts";
import { deviceTodayService } from "./device-today.service.ts";
import { heartRateService } from "./heart-rate.service.ts";
import { syncCheckpointService } from "./sync-checkpoint.service.ts";
import { background } from "../../shared/runtime/background.ts";
import { outbox } from "../../infrastructure/queue/outbox.ts";
import { eventHandlers } from "../events/handlers.ts";

const days = (req: Request, def: number) => z.coerce.number().int().refine((d) => [7, 14, 30, 90].includes(d)).default(def).parse(new URL(req.url).searchParams.get("days") ?? undefined);
const hrDays = (req: Request) => z.coerce.number().int().refine((d) => [7, 14, 30].includes(d)).default(7).parse(new URL(req.url).searchParams.get("days") ?? undefined);
const dayParam = (req: Request) => z.iso.date().parse(new URL(req.url).searchParams.get("date") ?? undefined);

export const deviceImportRoutes = {
  "/api/me/device-import/preferences": {
    GET: authenticated(async ({ session }) => ({ body: await deviceImportService.preferences(session.userId) })),
    PATCH: authenticated(async ({ req, session }) => ({ body: await deviceImportService.setPreferences(session.userId, await readJson(req, devicePreferencesSchema)) })),
  },
  "/api/me/device-import": {
    POST: authenticated(async ({ req, session }) => {
      const body = await deviceImportService.import(session.userId, await readJson(req, deviceImportSchema));
      background(outbox.drainUser(eventHandlers(), session.userId), "device_import_drain");
      return { body };
    }),
  },
  "/api/me/devices/status": { GET: authenticated(async ({ session }) => ({ body: await deviceQualityService.status(session.userId) })) },
  "/api/me/devices/today": { GET: authenticated(async ({ session }) => ({ body: await deviceTodayService.get(session.userId) })) },
  "/api/me/device-sync/checkpoints": {
    GET: authenticated(async ({ session }) => ({ body: await syncCheckpointService.list(session.userId) })),
    PUT: authenticated(async ({ req, session }) => ({ body: await syncCheckpointService.report(session.userId, await readJson(req, syncCheckpointSchema)) })),
  },
  "/api/me/heart-rate": { GET: authenticated(async ({ req, session }) => ({ body: await heartRateService.summary(session.userId, hrDays(req)) })) },
  "/api/me/heart-rate/day": { GET: authenticated(async ({ req, session }) => ({ body: await heartRateService.day(session.userId, dayParam(req)) })) },
  "/api/me/steps": { GET: authenticated(async ({ req, session }) => ({ body: await deviceImportService.steps(session.userId, days(req, 14)) })) },
  "/api/me/sleep": { GET: authenticated(async ({ req, session }) => ({ body: await deviceImportService.sleepSummary(session.userId, days(req, 14)) })) },
};
