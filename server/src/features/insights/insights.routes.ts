import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { nutritionService } from "../nutrition/nutrition.service.ts";
import { glucoseService } from "../glucose/glucose.service.ts";
import { weeklyService } from "./weekly.service.ts";
import { trendsService } from "./trends.service.ts";
import { activityService } from "../activity/activity.service.ts";
export const insightsRoutes = {
  "/api/me/summaries/daily": {
    GET: authenticated(async ({ req, session }) => {
      const date = z.iso
        .date()
        .optional()
        .parse(new URL(req.url).searchParams.get("date") ?? undefined);
      const [nutrition, glucose, activity] = await Promise.all([
        nutritionService.daily(session.userId, date),
        glucoseService.daily(session.userId, date),
        activityService.daily(session.userId, date),
      ]);
      return { body: { ...nutrition, glucose, activity } };
    }),
  },
  "/api/me/summaries/weekly": {
    GET: authenticated(async ({ req, session }) => ({
      body: await weeklyService.get(
        session.userId,
        z.iso.date().optional().parse(new URL(req.url).searchParams.get("date") ?? undefined),
      ),
    })),
  },
  "/api/me/trends": {
    GET: authenticated(async ({ req, session }) => {
      const days = z.coerce
        .number()
        .pipe(z.union([z.literal(7), z.literal(14), z.literal(30), z.literal(90)]))
        .default(14)
        .parse(new URL(req.url).searchParams.get("days") ?? undefined);
      return { body: await trendsService.get(session.userId, days) };
    }),
  },
};
