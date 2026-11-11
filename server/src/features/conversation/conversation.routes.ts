import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { messageCreateSchema } from "./conversation.schema.ts";
import { conversationService } from "./conversation.service.ts";

const seg = (req: Request, i: number) => z.uuid().parse(new URL(req.url).pathname.split("/")[i]);

export const conversationRoutes = {
  "/api/me/conversations": {
    GET: authenticated(async ({ session }) => ({ body: await conversationService.list(session.userId) })),
  },
  "/api/me/conversations/:id": {
    GET: authenticated(async ({ req, session }) => ({ body: await conversationService.get(session.userId, seg(req, 4)) })),
    DELETE: authenticated(async ({ req, session }) => ({ body: await conversationService.remove(session.userId, seg(req, 4)) })),
  },
  "/api/me/conversations/:id/messages": {
    POST: authenticated(async ({ req, session }) => {
      const result = await conversationService.post(session.userId, seg(req, 4), await readJson(req, messageCreateSchema));
      return { status: result.replayed ? 200 : 201, body: result };
    }),
  },
};
