import { isIP } from "node:net";
import type { Server } from "bun";
import { env } from "../../config/env.ts";
import { route } from "../../shared/http/handler.ts";
import { auth, CLIENT_IP_HEADER } from "./auth.ts";
import { resetPasswordPage, verifiedPage } from "./auth-pages.ts";

function clientIp(req: Request, server: Server<unknown>): string | undefined {
  if (env.TRUST_PROXY) {
    const forwarded = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
    if (forwarded && isIP(forwarded)) return forwarded;
  }
  return server.requestIP(req)?.address;
}

export const authRoutes = {
  "/api/auth/*": route(async ({ req, server }) => {
    if (new URL(req.url).pathname.startsWith("/api/auth/delete-user")) {
      return { status: 404, body: { error: { code: "NOT_FOUND", message: "Rute tidak ditemukan." } } };
    }
    const headers = new Headers(req.headers);
    headers.delete(CLIENT_IP_HEADER);
    const ip = clientIp(req, server);
    if (ip) headers.set(CLIENT_IP_HEADER, ip);
    return auth.handler(new Request(req, { headers }));
  }),
  "/auth/verified": route(async ({ req }) => verifiedPage(new URL(req.url).searchParams.has("error"))),
  "/auth/reset-password": route(async () => resetPasswordPage()),
};
