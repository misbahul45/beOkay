import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { labCreateSchema, labPatchSchema, labQuerySchema, vitalCreateSchema, vitalPatchSchema, vitalQuerySchema } from "./clinical.schema.ts";
import { clinicalService } from "./clinical.service.ts";

const id = (req: Request) => z.uuid().parse(new URL(req.url).pathname.split("/")[4]);
const query = (req: Request) => Object.fromEntries(new URL(req.url).searchParams);

export const clinicalRoutes = {
  "/api/me/clinical/summary": { GET: authenticated(async ({ session }) => ({ body: await clinicalService.summary(session.userId) })) },
  "/api/me/vitals": {
    GET: authenticated(async ({ req, session }) => ({ body: await clinicalService.listVitals(session.userId, vitalQuerySchema.parse(query(req))) })),
    POST: authenticated(async ({ req, session }) => ({ status: 201, body: await clinicalService.createVital(session.userId, await readJson(req, vitalCreateSchema)) })),
  },
  "/api/me/vitals/:id": {
    GET: authenticated(async ({ req, session }) => ({ body: await clinicalService.getVital(session.userId, id(req)) })),
    PATCH: authenticated(async ({ req, session }) => ({ body: await clinicalService.updateVital(session.userId, id(req), await readJson(req, vitalPatchSchema)) })),
  },
  "/api/me/vitals/:id/revisions": { GET: authenticated(async ({ req, session }) => ({ body: await clinicalService.vitalRevisions(session.userId, id(req)) })) },
  "/api/me/labs": {
    GET: authenticated(async ({ req, session }) => ({ body: await clinicalService.listLabs(session.userId, labQuerySchema.parse(query(req))) })),
    POST: authenticated(async ({ req, session }) => ({ status: 201, body: await clinicalService.createLab(session.userId, await readJson(req, labCreateSchema)) })),
  },
  "/api/me/labs/:id": {
    GET: authenticated(async ({ req, session }) => ({ body: await clinicalService.getLab(session.userId, id(req)) })),
    PATCH: authenticated(async ({ req, session }) => ({ body: await clinicalService.updateLab(session.userId, id(req), await readJson(req, labPatchSchema)) })),
  },
  "/api/me/labs/:id/revisions": { GET: authenticated(async ({ req, session }) => ({ body: await clinicalService.labRevisions(session.userId, id(req)) })) },
};
