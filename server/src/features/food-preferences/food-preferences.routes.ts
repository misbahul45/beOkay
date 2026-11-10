import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { preferenceCheckSchema, preferenceCreateSchema, preferenceListQuerySchema, preferencePatchSchema } from "./food-preferences.schema.ts";
import { foodPreferencesService } from "./food-preferences.service.ts";

const query = (req: Request) => Object.fromEntries(new URL(req.url).searchParams);

export const foodPreferencesRoutes = {
  "/api/me/food-preferences": {
    GET: authenticated(async ({ req, session }) => ({
      body: await foodPreferencesService.list(session.userId, preferenceListQuerySchema.parse(query(req)).archived === "true"),
    })),
    POST: authenticated(async ({ req, session }) => {
      const r = await foodPreferencesService.create(session.userId, await readJson(req, preferenceCreateSchema));
      return { status: r.created ? 201 : 200, body: r.item };
    }),
  },
  "/api/me/food-preferences/check": {
    POST: authenticated(async ({ req, session }) => ({
      body: await foodPreferencesService.check(session.userId, (await readJson(req, preferenceCheckSchema)).items),
    })),
  },
  "/api/me/food-preferences/:id": {
    PATCH: authenticated(async ({ req, session }) => ({
      body: await foodPreferencesService.update(session.userId, z.uuid().parse(new URL(req.url).pathname.split("/")[4]), await readJson(req, preferencePatchSchema)),
    })),
  },
};
