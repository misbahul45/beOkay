import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { pushRegisterSchema } from "./push.schema.ts";
import { pushService } from "./push.service.ts";

export const pushRoutes = {
  "/api/me/push-devices": {
    GET: authenticated(async ({ session }) => ({ body: await pushService.list(session.userId) })),
    POST: authenticated(async ({ req, session }) => {
      const r = await pushService.register(session.userId, await readJson(req, pushRegisterSchema));
      return { status: r.created ? 201 : 200, body: r.item };
    }),
  },
  "/api/me/push-devices/:id": {
    DELETE: authenticated(async ({ req, session }) => ({ body: await pushService.unregister(session.userId, z.uuid().parse(new URL(req.url).pathname.split("/")[4])) })),
  },
};
