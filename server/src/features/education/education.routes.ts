import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { educationService } from "./education.service.ts";

const key = (req: Request) => z.string().regex(/^[a-z0-9][a-z0-9-]{2,59}$/).parse(new URL(req.url).pathname.split("/")[4]);

export const educationRoutes = {
  "/api/education/modules": { GET: authenticated(async () => ({ body: await educationService.list() })) },
  "/api/education/modules/:key": { GET: authenticated(async ({ req }) => ({ body: await educationService.get(key(req)) })) },
};
