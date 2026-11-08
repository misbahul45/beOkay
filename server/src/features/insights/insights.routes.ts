import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { nutritionService } from "../nutrition/nutrition.service.ts";
import { glucoseService } from "../glucose/glucose.service.ts";
export const insightsRoutes = {
  "/api/me/summaries/daily": {
    GET: authenticated(async ({ req, session }) => {
      const date = z.iso
        .date()
        .optional()
        .parse(new URL(req.url).searchParams.get("date") ?? undefined);
      const [nutrition, glucose] = await Promise.all([
        nutritionService.daily(session.userId, date),
        glucoseService.daily(session.userId, date),
      ]);
      return { body: { ...nutrition, glucose } };
    }),
  },
};
