import type { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../database/prisma.ts";
import { logEvent } from "../../shared/http/logger.ts";

/**
 * Outbox transaksional: peristiwa ditulis DALAM transaksi yang sama dengan perubahan datanya (tidak ada peristiwa tanpa data, tidak ada
 * data tanpa peristiwa), lalu diproses pekerja di dalam proses API dengan retry, backoff, dan dead-letter. Pengiriman minimal satu kali;
 * penangan harus idempoten, dan `dedupeKey` mencegah peristiwa ganda.
 */
export const MAX_ATTEMPTS = 5;
const BASE_BACKOFF_MS = 5_000;

export type OutboxEvent = { id: string; userId: string | null; type: string; payload: Record<string, unknown>; attempts: number };
export type OutboxHandlers = Record<string, (event: OutboxEvent) => Promise<void>>;

export const outbox = {
  async enqueue(tx: Prisma.TransactionClient | typeof prisma, e: { userId: string | null; type: string; payload?: Record<string, unknown>; dedupeKey: string }) {
    await tx.outboxEvent.createMany({ data: [{ userId: e.userId, type: e.type, payload: (e.payload ?? {}) as Prisma.InputJsonObject, dedupeKey: e.dedupeKey }], skipDuplicates: true });
  },

  /** Klaim dengan FOR UPDATE SKIP LOCKED; klaim menaikkan `attempts` dan menjadwalkan ulang (jaring pengaman bila proses mati di tengah). */
  async claim(limit: number): Promise<OutboxEvent[]> {
    const rows = await prisma.$queryRaw<{ id: string; user_id: string | null; type: string; payload: Record<string, unknown>; attempts: number }[]>`
      UPDATE outbox_events SET attempts = attempts + 1,
        available_at = now() + (${BASE_BACKOFF_MS}::int * power(2, attempts))::int * interval '1 millisecond'
      WHERE id IN (SELECT id FROM outbox_events WHERE status = 'PENDING' AND available_at <= now() ORDER BY created_at LIMIT ${limit} FOR UPDATE SKIP LOCKED)
      RETURNING id, user_id, type, payload, attempts`;
    return rows.map((r) => ({ id: r.id, userId: r.user_id, type: r.type, payload: r.payload, attempts: r.attempts }));
  },

  async drain(handlers: OutboxHandlers, limit = 20): Promise<{ done: number; failed: number; dead: number }> {
    const batch = await this.claim(limit);
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
