import { timingSafeEqual } from "node:crypto";
import { env } from "../../config/env.ts";
import { route } from "../../shared/http/handler.ts";
import { jobStatus, runTick } from "./jobs.service.ts";

const notFound = { status: 404, body: { error: { code: "NOT_FOUND", message: "Rute tidak ditemukan." } } };

export function cronAuthorized(req: Request, secret = env.CRON_SECRET) {
  if (!secret) return false;
  const header = req.headers.get("authorization") ?? "";
  const given = header.startsWith("Bearer ") ? header.slice(7) : (req.headers.get("x-cron-secret") ?? "");
  const a = Buffer.from(given);
  const b = Buffer.from(secret);
  return a.length === b.length && timingSafeEqual(a, b);
}

const tick = route(async ({ req }) => {
  if (!cronAuthorized(req)) return notFound;
  const only = new URL(req.url).searchParams.get("only")?.split(",").filter((s) => /^[a-z_]{3,40}$/.test(s));
  return { body: await runTick(new Date(), { only }) };
});

export const jobRoutes = {
  "/internal/jobs/tick": { GET: tick, POST: tick },
  "/internal/jobs/status": {
    GET: route(async ({ req }) => (cronAuthorized(req) ? { body: { items: await jobStatus() } } : notFound)),
  },
};
