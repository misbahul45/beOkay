import type { Prisma } from "../../generated/prisma/client.ts";
import type { prisma } from "../../infrastructure/database/prisma.ts";
import { emitDomainEvent } from "../../infrastructure/queue/events.ts";

type Db = Prisma.TransactionClient | typeof prisma;

export const RECORD_KINDS = ["meal", "glucose", "activity", "medication_intake", "goal_checkin", "vital", "lab", "steps", "sleep", "cgm", "energy_checkin"] as const;
export type RecordKind = (typeof RECORD_KINDS)[number];
export type RecordAction = "created" | "corrected" | "archived";

export const PROJECTED_KINDS: readonly RecordKind[] = ["meal", "glucose", "activity", "medication_intake", "goal_checkin", "steps", "sleep"];

export type RecordEvent = {
  userId: string;
  kind: RecordKind;
  action: RecordAction;
  recordId: string;
  revision: number;
  occurredAt: Date;
  localDates: string[];
  timezone: string;
  source: string;
  quality?: string | null;
  provenance?: Record<string, unknown> | null;
  correlationId?: string | null;
};

export async function markDaysDirty(tx: Db, userId: string, localDates: string[]) {
  const dates = [...new Set(localDates)].map((d) => new Date(d + "T00:00:00Z"));
  if (!dates.length) return;
  await tx.dailyBehaviorFact.updateMany({ where: { userId, localDate: { in: dates } }, data: { dirty: true } });
}

export async function emitRecordEvent(tx: Db, e: RecordEvent) {
  const localDates = [...new Set(e.localDates)].sort();
  const inserted = await emitDomainEvent(tx, {
    userId: e.userId,
    type: `record.${e.action}`,
    dedupeKey: `record:${e.kind}:${e.recordId}:r${e.revision}:${e.action}`,
    payload: { kind: e.kind, recordId: e.recordId, localDates },
    source: e.source,
    sourceRecordId: e.recordId,
    occurredAt: e.occurredAt,
    timezone: e.timezone,
    revision: e.revision,
    consentScope: "health_data_processing",
    quality: e.quality ?? null,
    provenance: e.provenance ?? null,
    correlationId: e.correlationId ?? null,
  });
  if (PROJECTED_KINDS.includes(e.kind)) await markDaysDirty(tx, e.userId, localDates);
  return inserted;
}
