import { authenticated } from "../auth/guard.ts";
import { dishService } from "./dish.service.ts";

export const mlRoutes = {
  // Pemanasan tanpa isi: 202 selalu, agar klien tidak bisa menebak status persetujuan atau model dari jawabannya.
  "/api/me/ml/warmup": { POST: authenticated(async ({ session }) => { void dishService.warmup(session.userId); return { status: 202, body: { accepted: true } }; }) },
  "/api/me/ml/models": { GET: authenticated(async () => ({ body: await dishService.capabilities() })) },
};
