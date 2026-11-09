import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { calculateSchema, measureSchema } from "../nutrition/calculator.schema.ts";
import { calculatorService } from "../nutrition/calculator.service.ts";
import { foodDiscoveryService } from "./food-discovery.service.ts";

const seg = (req: Request, i: number) => new URL(req.url).pathname.split("/")[i]!;

export const foodDiscoveryRoutes = {
  "/api/me/foods/discover": {
    GET: authenticated(async ({ req, session }) => {
      const params = new URL(req.url).searchParams;
      const q = z.string().trim().min(2).max(80).parse(params.get("q"));
      const external = z.enum(["true", "false"]).default("false").parse(params.get("external") ?? "false") === "true";
      return { body: await foodDiscoveryService.discover(session.userId, q, external) };
    }),
  },
  "/api/me/foods/barcode/:code": {
    GET: authenticated(async ({ req, session }) => ({
      body: await foodDiscoveryService.barcode(session.userId, seg(req, 5)),
    })),
  },
  "/api/me/foods/:id/measures": {
    GET: authenticated(async ({ req, session }) => ({
      body: await calculatorService.listMeasures(session.userId, z.uuid().parse(seg(req, 4))),
    })),
    POST: authenticated(async ({ req, session }) => ({
      status: 201,
      body: await calculatorService.addMeasure(session.userId, z.uuid().parse(seg(req, 4)), await readJson(req, measureSchema)),
    })),
  },
  "/api/me/nutrition/calculate": {
    POST: authenticated(async ({ req, session }) => ({
      body: await calculatorService.calculate(session.userId, await readJson(req, calculateSchema)),
    })),
  },
};
