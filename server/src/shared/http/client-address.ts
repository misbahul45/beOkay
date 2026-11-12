import { isIP } from "node:net";
import type { Server } from "bun";
import { env } from "../../config/env.ts";

export function clientIp(req: Request, server?: Server<unknown>): string | undefined {
  if (env.TRUST_PROXY) {
    const forwarded = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
    if (forwarded && isIP(forwarded)) return forwarded;
  }
  return server?.requestIP?.(req)?.address;
}

export const clientAddress = (req: Request, server?: Server<unknown>) => clientIp(req, server) ?? "unknown";
