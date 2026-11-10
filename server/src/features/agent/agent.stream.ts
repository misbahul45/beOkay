import { prisma } from "../../infrastructure/database/prisma.ts";
import { agentService } from "./agent.service.ts";

/**
 * Server-Sent Events untuk satu run. Sumber kebenaran tetap tabel agent_run_events: klien yang putus menyambung lagi dengan
 * `Last-Event-ID` (atau ?after=) dan menerima ulang hanya peristiwa yang terlewat. Aliran berakhir dengan peristiwa `state`
 * (tampilan run lengkap) begitu run berhenti, termasuk saat menunggu keputusan pengguna.
 */
export const STREAM_POLL_MS = 400;
export const STREAM_MAX_MS = 45_000;
const HEARTBEAT_MS = 10_000;
const SETTLED = new Set(["COMPLETED", "FAILED", "BLOCKED", "CANCELLED", "EXPIRED", "WAITING_FOR_USER"]);

export async function streamRun(userId: string, runId: string, after: number, signal: AbortSignal): Promise<Response> {
  await agentService.getRun(userId, runId); // 404 untuk run milik orang lain, sebelum aliran dibuka
  const enc = new TextEncoder();
  let last = Math.max(0, after);
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const started = Date.now();
      let lastBeat = Date.now();
      const send = (chunk: string) => controller.enqueue(enc.encode(chunk));
      try {
        send("retry: 2000\n\n");
        while (!signal.aborted && Date.now() - started < STREAM_MAX_MS) {
          const events = await prisma.agentRunEvent.findMany({ where: { runId, seq: { gt: last }, run: { userId } }, orderBy: { seq: "asc" }, take: 100 });
          for (const e of events) {
            send(`id: ${e.seq}\nevent: ${e.type}\ndata: ${JSON.stringify({ seq: e.seq, type: e.type, payload: e.payload })}\n\n`);
            last = e.seq;
            lastBeat = Date.now();
          }
          const run = await agentService.getRun(userId, runId); // juga menjalankan pemulihan run macet, kedaluwarsa, dan pencabutan consent
          if (SETTLED.has(run.status) && events.length < 100) {
            const tail = await prisma.agentRunEvent.findMany({ where: { runId, seq: { gt: last } }, orderBy: { seq: "asc" } });
            for (const e of tail) { send(`id: ${e.seq}\nevent: ${e.type}\ndata: ${JSON.stringify({ seq: e.seq, type: e.type, payload: e.payload })}\n\n`); last = e.seq; }
            send(`event: state\ndata: ${JSON.stringify(await agentService.getRun(userId, runId))}\n\n`);
            break;
          }
          if (Date.now() - lastBeat > HEARTBEAT_MS) { send(": heartbeat\n\n"); lastBeat = Date.now(); }
          await new Promise((r) => setTimeout(r, STREAM_POLL_MS));
        }
      } catch {
        // Aliran putus; klien menyambung ulang dengan Last-Event-ID.
      } finally {
        try { controller.close(); } catch { /* sudah ditutup */ }
      }
    },
  });
  return new Response(stream, { headers: { "content-type": "text/event-stream; charset=utf-8", "cache-control": "no-store", "x-accel-buffering": "no" } });
}
