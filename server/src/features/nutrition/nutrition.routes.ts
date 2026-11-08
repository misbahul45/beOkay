import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { nutritionService } from "./nutrition.service.ts";
import {
  foodSchema,
  mealCreateSchema,
  mealPatchSchema,
  mealQuerySchema,
} from "./nutrition.schema.ts";
const recordId = (req: Request) =>
  z.uuid().parse(new URL(req.url).pathname.split("/")[4]);
export const nutritionRoutes = {
  "/api/foods/search": {
    GET: authenticated(async ({ req, session }) => ({
      body: await nutritionService.searchFoods(
        session.userId,
        z
          .string()
          .trim()
          .min(2)
          .max(80)
          .parse(new URL(req.url).searchParams.get("q")),
      ),
    })),
  },
  "/api/me/foods": {
    POST: authenticated(async ({ req, session }) => ({
      status: 201,
      body: await nutritionService.createFood(
        session.userId,
        await readJson(req, foodSchema),
      ),
    })),
  },
  "/api/me/foods/:id": {
    PATCH: authenticated(async ({ req, session }) => ({
      body: await nutritionService.updateFood(
        session.userId,
        recordId(req),
        await readJson(req, foodSchema),
      ),
    })),
  },
  "/api/me/meals": {
    GET: authenticated(async ({ req, session }) => ({
      body: await nutritionService.list(
        session.userId,
        mealQuerySchema.parse(
          Object.fromEntries(new URL(req.url).searchParams),
        ),
      ),
    })),
    POST: authenticated(async ({ req, session }) => ({
      status: 201,
      body: await nutritionService.create(
        session.userId,
        await readJson(req, mealCreateSchema),
      ),
    })),
  },
  "/api/me/meals/:id": {
    GET: authenticated(async ({ req, session }) => ({
      body: await nutritionService.get(session.userId, recordId(req)),
    })),
    PATCH: authenticated(async ({ req, session }) => ({
      body: await nutritionService.update(
        session.userId,
        recordId(req),
        await readJson(req, mealPatchSchema),
      ),
    })),
  },
  "/api/me/meals/:id/revisions": {
    GET: authenticated(async ({ req, session }) => ({
      body: await nutritionService.revisions(session.userId, recordId(req)),
    })),
  },
  "/api/me/summaries/daily": {
    GET: authenticated(async ({ req, session }) => ({
      body: await nutritionService.daily(
        session.userId,
        z.iso
          .date()
          .optional()
          .parse(new URL(req.url).searchParams.get("date") ?? undefined),
      ),
    })),
  },
  "/api/me/timeline": {
    GET: authenticated(async ({ req, session }) => {
      const page = await nutritionService.list(
        session.userId,
        mealQuerySchema.parse(
          Object.fromEntries(new URL(req.url).searchParams),
        ),
      );
      return {
        body: {
          supportedDomains: ["meal"],
          nextCursor: page.nextCursor,
          items: page.items.map((meal) => ({
            domain: "meal",
            recordId: meal.id,
            occurredAt: meal.consumedAt,
            localDate: meal.localDate,
            localTime: meal.localTime,
            category: meal.category,
            itemCount: meal.items.length,
          })),
        },
      };
    }),
  },
};
