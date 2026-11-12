import type { Server } from "bun";
import { randomBytes } from "node:crypto";
import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson, route } from "../../shared/http/handler.ts";
import { pageCsp } from "../share/share.page.ts";
import { renderCompanion, renderCompanionUnavailable } from "./companion.page.ts";
import { companionSchema, companionService } from "./companion.service.ts";
import { clientAddress } from "../../shared/http/client-address.ts";

const id = (req: Request) => z.uuid().parse(new URL(req.url).pathname.split("/")[4]);
const html = (body: string, status: number, nonce: string) => new Response(body, { status, headers: { "content-type": "text/html; charset=utf-8", "content-security-policy": pageCsp(nonce) } });

export const companionRoutes = {
  "/api/me/companions": {
    GET: authenticated(async ({ session }) => ({ body: await companionService.list(session.userId) })),
    POST: authenticated(async ({ req, session }) => ({ status: 201, body: await companionService.create(session.userId, await readJson(req, companionSchema)) })),
  },
  "/api/me/companions/:id/revoke": { POST: authenticated(async ({ req, session }) => ({ body: await companionService.revoke(session.userId, id(req)) })) },
  "/c/:token": {
    GET: route(async ({ req, server }) => {
      const token = new URL(req.url).pathname.split("/")[2] ?? "";
      const r = await companionService.resolve(token, clientAddress(req, server as Server<unknown> | undefined));
      const nonce = randomBytes(16).toString("base64");
      return r.status === 200 ? html(renderCompanion(r.summary!, nonce), 200, nonce) : html(renderCompanionUnavailable(r.status, nonce), r.status, nonce);
    }),
  },
};
