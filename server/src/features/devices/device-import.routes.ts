import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { deviceImportSchema, devicePreferencesSchema } from "./device-import.schema.ts";
import { deviceImportService } from "./device-import.service.ts";
import { deviceQualityService } from "./quality.service.ts";
import { background } from "../../shared/runtime/background.ts";
import { outbox } from "../../infrastructure/queue/outbox.ts";
import { eventHandlers } from "../events/handlers.ts";

const days = (req: Request, def: number) => z.coerce.number().int().refine((d) => [7, 14, 30, 90].includes(d)).default(def).parse(new URL(req.url).searchParams.get("days") ?? undefined);

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
  "/api/me/steps": { GET: authenticated(async ({ req, session }) => ({ body: await deviceImportService.steps(session.userId, days(req, 14)) })) },
  "/api/me/sleep": { GET: authenticated(async ({ req, session }) => ({ body: await deviceImportService.sleepSummary(session.userId, days(req, 14)) })) },
};
