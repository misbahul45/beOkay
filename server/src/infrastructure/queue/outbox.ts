import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../database/prisma.ts";
import { logEvent } from "../../shared/http/logger.ts";

/**
 * Outbox transaksional: peristiwa ditulis DALAM transaksi yang sama dengan perubahan datanya (tidak ada peristiwa tanpa data, tidak ada
 * data tanpa peristiwa), lalu diproses pekerja di dalam proses API dengan retry, backoff, dan dead-letter. Pengiriman minimal satu kali;
 * penangan harus idempoten, dan `dedupeKey` mencegah peristiwa ganda.
 */
export const MAX_ATTEMPTS = 5;
const BASE_BACKOFF_MS = 5_000;

export type EventEnvelope = {
  source?: string | null;
  sourceRecordId?: string | null;
  occurredAt?: Date | null;
  timezone?: string | null;
  revision?: number | null;
  consentScope?: string | null;
  quality?: string | null;
  provenance?: Record<string, unknown> | null;
  correlationId?: string | null;
};
export const EVENT_SCHEMA_VERSION = 1;
export type OutboxEvent = { id: string; userId: string | null; type: string; payload: Record<string, unknown>; attempts: number };
export type OutboxHandlers = Record<string, (event: OutboxEvent) => Promise<void>>;

export const outbox = {
  async enqueue(tx: Prisma.TransactionClient | typeof prisma, e: { userId: string | null; type: string; payload?: Record<string, unknown>; dedupeKey: string; envelope?: EventEnvelope }) {
    const env = e.envelope ?? {};
    const inserted = await tx.outboxEvent.createMany({
      data: [{
        userId: e.userId,
        type: e.type,
        payload: (e.payload ?? {}) as Prisma.InputJsonObject,
        dedupeKey: e.dedupeKey,
        source: env.source ?? null,
        sourceRecordId: env.sourceRecordId ?? null,
        occurredAt: env.occurredAt ?? null,
        timezone: env.timezone ?? null,
        revision: env.revision ?? null,
        consentScope: env.consentScope ?? null,
        quality: env.quality ?? null,
        provenance: env.provenance ? (env.provenance as Prisma.InputJsonObject) : undefined,
        correlationId: env.correlationId ?? null,
        schemaVersion: EVENT_SCHEMA_VERSION,
      }],
      skipDuplicates: true,
    });
    return inserted.count === 1;
  },

  async drainUser(handlers: OutboxHandlers, userId: string, limit = 50) {
    const pending = await prisma.outboxEvent.count({ where: { userId, status: "PENDING", availableAt: { lte: new Date() } } });
    if (!pending) return { done: 0, failed: 0, dead: 0 };
    return this.drain(handlers, Math.min(limit, Math.max(pending, 20)), userId);
  },

  /** Klaim dengan FOR UPDATE SKIP LOCKED; klaim menaikkan `attempts` dan menjadwalkan ulang (jaring pengaman bila proses mati di tengah). */
  async claim(limit: number, userId?: string): Promise<OutboxEvent[]> {
    const scope = userId ? Prisma.sql`AND user_id = ${userId}::uuid` : Prisma.empty;
    const rows = await prisma.$queryRaw<{ id: string; user_id: string | null; type: string; payload: Record<string, unknown>; attempts: number }[]>`
      UPDATE outbox_events SET attempts = attempts + 1,
        available_at = now() + (${BASE_BACKOFF_MS}::int * power(2, attempts))::int * interval '1 millisecond'
      WHERE id IN (SELECT id FROM outbox_events WHERE status = 'PENDING' AND available_at <= now() ${scope} ORDER BY created_at LIMIT ${limit} FOR UPDATE SKIP LOCKED)
      RETURNING id, user_id, type, payload, attempts`;
    return rows.map((r) => ({ id: r.id, userId: r.user_id, type: r.type, payload: r.payload, attempts: r.attempts }));
  },

  async drain(handlers: OutboxHandlers, limit = 20, userId?: string): Promise<{ done: number; failed: number; dead: number }> {
    const batch = await this.claim(limit, userId);
    let done = 0, failed = 0, dead = 0;
    for (const ev of batch) {
      const handler = handlers[ev.type];
      try {
        if (!handler) throw new Error(`NO_HANDLER:${ev.type}`);
        await handler(ev);
        await prisma.outboxEvent.update({ where: { id: ev.id }, data: { status: "DONE", processedAt: new Date(), lastError: null } });
        done++;
      } catch (e) {
        const msg = (e instanceof Error ? e.message : "UNKNOWN").slice(0, 200);
        const isDead = ev.attempts >= MAX_ATTEMPTS;
        await prisma.outboxEvent.update({ where: { id: ev.id }, data: { lastError: msg, ...(isDead ? { status: "DEAD", processedAt: new Date() } : {}) } });
        logEvent(isDead ? "error" : "warn", "outbox_event_failed", { type: ev.type, attempts: ev.attempts, dead: isDead });
        isDead ? dead++ : failed++;
      }
    }
    return { done, failed, dead };
  },

  async stats() {
    const rows = await prisma.outboxEvent.groupBy({ by: ["status"], _count: { _all: true } });
    return Object.fromEntries(rows.map((r) => [r.status, r._count._all]));
  },
};
