import type { Prisma } from "../../generated/prisma/client.ts";

type Db = Pick<Prisma.TransactionClient, "auditEvent" | "summaryProjection">;
export type AuditEvent = { userId: string; eventType: string; metadata?: Prisma.InputJsonObject };
export type AuditListener = (db: Db, event: AuditEvent) => Promise<void>;

const SOURCE_PREFIXES = ["meal_", "glucose_", "activity_", "medication_", "goal_", "consent_", "preferences_", "food_", "vital_", "lab_"];
const listeners: AuditListener[] = [];

export function onAudit(listener: AuditListener) {
  if (!listeners.includes(listener)) listeners.push(listener);
}

export async function recordAudit(db: Db, event: AuditEvent) {
  await db.auditEvent.create({
    data: { userId: event.userId, eventType: event.eventType, metadata: event.metadata ?? undefined },
  });
  if (SOURCE_PREFIXES.some((p) => event.eventType.startsWith(p))) {
    await db.summaryProjection.updateMany({
      where: { userId: event.userId, freshnessStatus: "CURRENT" },
      data: { freshnessStatus: "STALE" },
    });
  }
  for (const listener of listeners) await listener(db, event);
}
