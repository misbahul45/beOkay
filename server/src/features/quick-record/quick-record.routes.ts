import { authenticated } from "../auth/guard.ts";
import { quickRecordService } from "./quick-record.service.ts";

export const quickRecordRoutes = {
  "/api/me/quick-record/suggestions": { GET: authenticated(async ({ session }) => ({ body: await quickRecordService.suggestions(session.userId) })) },
};
