import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { memoryService } from "./memory.service.ts";

const seg = (req: Request, i: number) => z.uuid().parse(new URL(req.url).pathname.split("/")[i]);
const content = z
  .string()
  .trim()
  .min(1)
  .max(160)
  .regex(/^[^\x00-\x1F\x7F]*$/);
const memoryPatchSchema = z.object({ content, expectedVersion: z.number().int().min(1) }).strict();
const memoryPreferenceSchema = z.object({ enabled: z.boolean() }).strict();

export const memoryRoutes = {
  "/api/me/memories": {
    GET: authenticated(async ({ session }) => ({ body: await memoryService.list(session.userId) })),
    DELETE: authenticated(async ({ session }) => ({ body: await memoryService.removeAll(session.userId) })),
  },
  "/api/me/memories/:id": {
    PATCH: authenticated(async ({ req, session }) => ({ body: await memoryService.update(session.userId, seg(req, 4), await readJson(req, memoryPatchSchema)) })),
    DELETE: authenticated(async ({ req, session }) => ({ body: await memoryService.remove(session.userId, seg(req, 4)) })),
  },
  "/api/me/memories/:id/confirm": {
    POST: authenticated(async ({ req, session }) => ({ body: await memoryService.confirm(session.userId, seg(req, 4)) })),
  },
  "/api/me/memories/:id/pause": {
    POST: authenticated(async ({ req, session }) => ({ body: await memoryService.pause(session.userId, seg(req, 4)) })),
  },
  "/api/me/memories/:id/resume": {
    POST: authenticated(async ({ req, session }) => ({ body: await memoryService.resume(session.userId, seg(req, 4)) })),
  },
  "/api/me/memories/:id/history": {
    GET: authenticated(async ({ req, session }) => ({ body: await memoryService.history(session.userId, seg(req, 4)) })),
  },
  "/api/me/memories/:id/dismiss": {
    POST: authenticated(async ({ req, session }) => ({ body: await memoryService.dismiss(session.userId, seg(req, 4)) })),
  },
  "/api/me/memory-preferences": {
    PATCH: authenticated(async ({ req, session }) => ({ body: await memoryService.setEnabled(session.userId, (await readJson(req, memoryPreferenceSchema)).enabled) })),
  },
};
