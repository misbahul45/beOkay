import { authenticated } from "../auth/guard.ts";
import { readJson, route } from "../../shared/http/handler.ts";
import { grantConsentSchema, withdrawConsentSchema } from "./consent.schema.ts";
import { consentService } from "./consent.service.ts";

export const consentRoutes = {
  "/api/consent-policies/current": { GET: route(async () => ({ body: consentService.currentPolicy() })) },
  "/api/me/consents": {
    GET: authenticated(async ({ session }) => ({ body: await consentService.overview(session.userId) })),
    POST: authenticated(async ({ req, session }) => {
      const input = await readJson(req, grantConsentSchema);
      return { body: await consentService.grant(session.userId, input) };
    }),
  },
  "/api/me/consents/withdraw": {
    POST: authenticated(async ({ req, session }) => {
      const input = await readJson(req, withdrawConsentSchema);
      return { body: await consentService.withdraw(session.userId, input) };
    }),
  },
};
