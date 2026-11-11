import { authenticated } from "../auth/guard.ts";
import { readJson } from "../../shared/http/handler.ts";
import { deleteAccountSchema } from "./account.schema.ts";
import { accountService } from "./account.service.ts";

export const accountRoutes = {
  "/api/me/account/delete": {
    POST: authenticated(async ({ req, session }) => ({
      body: await accountService.delete(session.userId, req.headers, await readJson(req, deleteAccountSchema)),
    })),
  },
};
