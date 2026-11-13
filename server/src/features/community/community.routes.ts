import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { communityService } from "./community.service.ts";
import { recognitionService } from "./recognition.service.ts";
import { moderationService, reportSchema } from "./moderation.service.ts";

const id = (req: Request, i: number) => z.uuid().parse(new URL(req.url).pathname.split("/")[i]);
const alias = z.object({ alias: z.string().trim().min(3).max(20) }).strict();
const join = z.object({ leaderboardVisible: z.boolean().default(false) }).strict();
const vis = z.object({ visible: z.boolean() }).strict();
const checkin = z.object({ localDate: z.iso.date().optional() }).strict();
const highlights = z.object({ highlightsEnabled: z.boolean() }).strict();
const page = z.object({ limit: z.coerce.number().int().min(1).max(50).default(20), offset: z.coerce.number().int().min(0).max(5000).default(0) });

export const communityRoutes = {
  "/api/regions": { GET: authenticated(async () => ({ body: await communityService.regions() })) },
  "/api/me/communities": {
    GET: authenticated(async ({ req, session }) => ({ body: await communityService.communities(session.userId, z.string().regex(/^[0-9]{2}$/).parse(new URL(req.url).searchParams.get("regionCode"))) })),
  },
  "/api/me/communities/mine": { GET: authenticated(async ({ session }) => ({ body: await communityService.mine(session.userId) })) },
  "/api/me/communities/:id/join": { POST: authenticated(async ({ req, session }) => { const r = await communityService.join(session.userId, id(req, 4), (await readJson(req, alias)).alias); return { status: r.created ? 201 : 200, body: r }; }) },
  "/api/me/communities/:id/alias": { PATCH: authenticated(async ({ req, session }) => ({ body: await communityService.setAlias(session.userId, id(req, 4), (await readJson(req, alias)).alias) })) },
  "/api/me/communities/:id/leave": { POST: authenticated(async ({ req, session }) => ({ body: await communityService.leave(session.userId, id(req, 4)) })) },
  "/api/me/communities/:id/challenges": { GET: authenticated(async ({ req, session }) => ({ body: await communityService.challenges(session.userId, id(req, 4)) })) },
  "/api/me/community/overview": { GET: authenticated(async ({ session }) => ({ body: await communityService.overview(session.userId) })) },
  "/api/me/community/privacy": {
    GET: authenticated(async ({ session }) => ({ body: await communityService.privacy(session.userId) })),
    PATCH: authenticated(async ({ req, session }) => ({ body: await communityService.setHighlights(session.userId, (await readJson(req, highlights)).highlightsEnabled) })),
  },
  "/api/me/community/privacy/hide-leaderboards": { POST: authenticated(async ({ session }) => ({ body: await communityService.hideFromAllLeaderboards(session.userId) })) },
  "/api/me/recognitions": { GET: authenticated(async ({ session }) => ({ body: await recognitionService.list(session.userId) })) },
  "/api/me/challenges/history": { GET: authenticated(async ({ session }) => ({ body: await communityService.history(session.userId) })) },
  "/api/me/challenges/:id": { GET: authenticated(async ({ req, session }) => ({ body: await communityService.challenge(session.userId, id(req, 4)) })) },
  "/api/me/challenges/:id/join": { POST: authenticated(async ({ req, session }) => ({ status: 201, body: await communityService.joinChallenge(session.userId, id(req, 4), (await readJson(req, join)).leaderboardVisible) })) },
  "/api/me/challenges/:id/leave": { POST: authenticated(async ({ req, session }) => ({ body: await communityService.leaveChallenge(session.userId, id(req, 4)) })) },
  "/api/me/challenges/:id/visibility": { PATCH: authenticated(async ({ req, session }) => ({ body: await communityService.setVisibility(session.userId, id(req, 4), (await readJson(req, vis)).visible) })) },
  "/api/me/challenges/:id/checkins": { POST: authenticated(async ({ req, session }) => ({ status: 201, body: await communityService.checkin(session.userId, id(req, 4), (await readJson(req, checkin)).localDate) })) },
  "/api/me/challenges/:id/team": { GET: authenticated(async ({ req, session }) => ({ body: await communityService.team(session.userId, id(req, 4)) })) },
  "/api/me/challenges/:id/progress": { GET: authenticated(async ({ req, session }) => ({ body: await communityService.progress(session.userId, id(req, 4)) })) },
  "/api/me/challenges/:id/reports": { POST: authenticated(async ({ req, session }) => ({ status: 201, body: await moderationService.report(session.userId, id(req, 4), await readJson(req, reportSchema)) })) },
  "/api/me/challenges/:id/leaderboard": { GET: authenticated(async ({ req, session }) => ({ body: await communityService.leaderboard(session.userId, id(req, 4), page.parse(Object.fromEntries(new URL(req.url).searchParams))) })) },
};
