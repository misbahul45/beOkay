import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { timelineService } from "./timeline.service.ts";
export const timelineQuery = z
  .object({
    date: z.iso.date().optional(),
    domain: z.enum(["all", "meal", "glucose"]).default("all"),
    cursor: z.string().max(300).optional(),
    limit: z.coerce.number().int().min(1).max(30).default(20),
    archived: z.enum(["true", "false"]).default("false"),
  })
  .strict();
export const timelineRoutes = {
  "/api/me/timeline": {
    GET: authenticated(async ({ req, session }) => ({
      body: await timelineService.list(
        session.userId,
        timelineQuery.parse(Object.fromEntries(new URL(req.url).searchParams)),
      ),
    })),
  },
};
