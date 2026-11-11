import type { Server } from "bun";
import { z } from "zod";
import type { SocketData } from "../../infrastructure/realtime/realtime.ts";
import { readJson } from "../../shared/http/handler.ts";
import { authenticated, resolveSession } from "../auth/guard.ts";
import { NOTIFICATION_KINDS, notificationService } from "./notification.service.ts";

const seg = (req: Request, i: number) => z.uuid().parse(new URL(req.url).pathname.split("/")[i]);
const listQuery = z.object({ cursor: z.uuid().optional(), limit: z.coerce.number().int().min(1).max(50).default(20) }).strict();
const prefSchema = z
  .object({ pushEnabled: z.boolean().optional(), mutedKinds: z.array(z.enum(NOTIFICATION_KINDS)).max(NOTIFICATION_KINDS.length).optional() })
  .strict()
  .refine((v) => v.pushEnabled !== undefined || v.mutedKinds !== undefined, "no changes");

export const notificationRoutes = {
  "/api/me/notifications": { GET: authenticated(async ({ req, session }) => ({ body: await notificationService.list(session.userId, listQuery.parse(Object.fromEntries(new URL(req.url).searchParams))) })) },
  "/api/me/notifications/unread-count": { GET: authenticated(async ({ session }) => ({ body: await notificationService.unreadCount(session.userId) })) },
  "/api/me/notifications/read-all": { POST: authenticated(async ({ session }) => ({ body: await notificationService.markAllRead(session.userId) })) },
  "/api/me/notifications/:id/read": { POST: authenticated(async ({ req, session }) => ({ body: await notificationService.markRead(session.userId, seg(req, 4)) })) },
  "/api/me/notification-preferences": {
    GET: authenticated(async ({ session }) => ({ body: await notificationService.getPreferences(session.userId) })),
    PATCH: authenticated(async ({ req, session }) => ({ body: await notificationService.updatePreferences(session.userId, await readJson(req, prefSchema)) })),
  },
};

export async function realtimeUpgrade(req: Request, server: Server<SocketData>): Promise<Response | undefined> {
  const session = await resolveSession(req.headers);
  if (!session || !session.emailVerified) return Response.json({ error: { code: "UNAUTHENTICATED", message: "Sesi tidak valid atau sudah berakhir." } }, { status: 401 });
  if (server.upgrade(req, { data: { userId: session.userId, sessionId: session.sessionId, topics: new Set<string>(), checkedAt: Date.now() } })) return undefined;
  return Response.json({ error: { code: "UPGRADE_REQUIRED", message: "Gunakan koneksi WebSocket." } }, { status: 426 });
}
