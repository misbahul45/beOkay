import type { Prisma } from "../../generated/prisma/client.ts";

type Db = Pick<Prisma.TransactionClient, "auditEvent" | "summaryProjection">;

/** Peristiwa yang mengubah data sumber ringkasan; proyeksi pengguna ditandai STALE. */
const SOURCE_PREFIXES = ["meal_", "glucose_", "activity_", "medication_", "goal_", "consent_", "preferences_", "food_"];

export async function recordAudit(
  db: Db,
  event: { userId: string; eventType: string; metadata?: Prisma.InputJsonObject },
) {
  await db.auditEvent.create({
    data: { userId: event.userId, eventType: event.eventType, metadata: event.metadata ?? undefined },
  });
  if (SOURCE_PREFIXES.some((p) => event.eventType.startsWith(p))) {
    await db.summaryProjection.updateMany({
      where: { userId: event.userId, freshnessStatus: "CURRENT" },
      data: { freshnessStatus: "STALE" },
    });
  }
}
