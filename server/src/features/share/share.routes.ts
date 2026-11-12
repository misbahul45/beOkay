import type { Server } from "bun";
import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson, route } from "../../shared/http/handler.ts";
import { reportSummaryService } from "./report-summary.service.ts";
import { randomBytes } from "node:crypto";
import { pageCsp, renderSummary, renderUnavailable } from "./share.page.ts";
import { shareLinkSchema, shareService } from "./share.service.ts";
import { clientAddress } from "../../shared/http/client-address.ts";

const id = (req: Request) => z.uuid().parse(new URL(req.url).pathname.split("/")[4]);
const period = (req: Request) => z.coerce.number().int().refine((d) => d === 14 || d === 30 || d === 90).default(30).parse(new URL(req.url).searchParams.get("days") ?? undefined) as 14 | 30 | 90;
const html = (body: string, status: number, nonce: string) => new Response(body, { status, headers: { "content-type": "text/html; charset=utf-8", "content-security-policy": pageCsp(nonce) } });

export const shareRoutes = {
  "/api/me/report-summary": { GET: authenticated(async ({ req, session }) => ({ body: await reportSummaryService.build(session.userId, period(req)) })) },
  "/api/me/share-links": {
    GET: authenticated(async ({ session }) => ({ body: await shareService.list(session.userId) })),
    POST: authenticated(async ({ req, session }) => ({ status: 201, body: await shareService.create(session.userId, await readJson(req, shareLinkSchema)) })),
  },
  "/api/me/share-links/:id/revoke": { POST: authenticated(async ({ req, session }) => ({ body: await shareService.revoke(session.userId, id(req)) })) },
  "/s/:token": {
    GET: route(async ({ req, server }) => {
      const token = new URL(req.url).pathname.split("/")[2] ?? "";
      const client = clientAddress(req, server as Server<unknown>);
      const r = await shareService.resolve(token, client);
      const nonce = randomBytes(16).toString("base64");
      return r.status === 200 ? html(renderSummary(r.summary!, r.expiresAt!, nonce), 200, nonce) : html(renderUnavailable(r.status, nonce), r.status, nonce);
    }),
  },
};
