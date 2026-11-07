import type { Prisma } from "../../generated/prisma/client.ts";

type Db = Pick<Prisma.TransactionClient, "auditEvent">;

export async function recordAudit(
  db: Db,
  event: { userId: string; eventType: string; metadata?: Prisma.InputJsonObject },
) {
  await db.auditEvent.create({
    data: { userId: event.userId, eventType: event.eventType, metadata: event.metadata ?? undefined },
  });
}
