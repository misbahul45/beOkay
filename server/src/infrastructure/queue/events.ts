import type { Prisma } from "../../generated/prisma/client.ts";
import type { prisma } from "../database/prisma.ts";
import { outbox, type EventEnvelope } from "./outbox.ts";

type Db = Prisma.TransactionClient | typeof prisma;

export const DOMAIN_EVENT_TYPES = [
  "record.created",
  "record.corrected",
  "record.archived",
  "device.imported",
  "consent.granted",
  "consent.withdrawn",
  "memory.changed",
  "journey.changed",
  "challenge.joined",
  "challenge.left",
  "challenge.scored",
] as const;
export type DomainEventType = (typeof DOMAIN_EVENT_TYPES)[number];

export async function emitDomainEvent(
  tx: Db,
  e: { userId: string; type: DomainEventType; dedupeKey: string; payload?: Record<string, unknown> } & EventEnvelope,
) {
  const { userId, type, dedupeKey, payload, ...envelope } = e;
  return outbox.enqueue(tx, { userId, type, dedupeKey, payload, envelope });
}
