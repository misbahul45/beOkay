import { authenticated } from "../auth/guard.ts";
import { exportService } from "./export.service.ts";

export const exportRoutes = {
  "/api/me/export": {
    GET: authenticated(async ({ session }) => {
      const bundle = await exportService.build(session.userId);
      const stamp = bundle.generatedAt.slice(0, 10);
      return new Response(JSON.stringify(bundle), {
        status: 200,
        headers: { "content-type": "application/json; charset=utf-8", "content-disposition": `attachment; filename="beokay-data-${stamp}.json"` },
      });
    }),
  },
};
