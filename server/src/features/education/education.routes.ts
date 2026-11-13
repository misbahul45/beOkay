import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { cohortService } from "../cohort/cohort.service.ts";
import { educationService } from "./education.service.ts";

const key = (req: Request) => z.string().regex(/^[a-z0-9][a-z0-9-]{2,59}$/).parse(new URL(req.url).pathname.split("/")[4]);

export const educationRoutes = {
  "/api/education/modules": { GET: authenticated(async ({ session }) => ({ body: await educationService.list(await cohortService.journeyOf(session.userId)) })) },
  "/api/education/modules/:key": { GET: authenticated(async ({ req, session }) => ({ body: await educationService.get(key(req), await cohortService.journeyOf(session.userId)) })) },
};
