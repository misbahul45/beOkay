import { createHash } from "node:crypto";
import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { consentService } from "../consent/consent.service.ts";
import { emitRecordEvent } from "../events/record-events.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { activityEnd } from "./activity.model.ts";
import { overlaps, type ImportSession } from "./activity-import.model.ts";

export type ImportOutcome = {
  externalId: string;
  status: "CREATED" | "CREATED_NEEDS_REVIEW" | "DUPLICATE" | "REJECTED";
  id?: string;
  reason?: string;
};

/**
 * Impor sesi aktivitas dari perangkat. Aturan:
 * - idempoten per (sumber, externalId): pengulangan tidak membuat baris baru;
 * - sesi impor berstatus device_reported, bukan user_reported;
 * - sesi yang bertabrakan waktu dengan catatan lain (manual atau impor) masuk needs_review dan tidak dihitung
 *   sampai pengguna memeriksanya, agar tidak ada penghitungan ganda;
 * - tidak ada metrik yang dikarang: jarak/langkah tetap null bila tidak dikirim.
 */
export const activityImportService = {
  async import(userId: string, source: "health_connect" | "apple_health", sessions: ImportSession[], now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    const { timezone } = await preferencesService.get(userId);
    const results: ImportOutcome[] = [];
    for (const s of sessions) {
      const start = new Date(s.startedAt);
      const end = activityEnd(start, s.durationMinutes);
      if (end.getTime() > now.getTime() + 300_000) {
        results.push({ externalId: s.externalId, status: "REJECTED", reason: "ACTIVITY_NOT_COMPLETED" });
        continue;
      }
      try {
        const outcome = await prisma.$transaction(async (tx) => {
          const existing = await tx.activitySession.findUnique({ where: { userId_source_externalId: { userId, source, externalId: s.externalId } } });
          if (existing) return { externalId: s.externalId, status: "DUPLICATE" as const, id: existing.id };
          const clash = await tx.activitySession.findFirst({
            where: { userId, archivedAt: null, startedAt: { lt: end }, endedAt: { gt: start } },
            select: { id: true, startedAt: true, endedAt: true, source: true },
          });
          const needsReview = Boolean(clash && overlaps(start, end, clash.startedAt, clash.endedAt));
          const hash = createHash("sha256").update(JSON.stringify({ source, ...s })).digest("hex");
          const saved = await tx.activitySession.create({
            data: {
              userId,
              activityType: s.activityType,
              startedAt: start,
              endedAt: end,
              durationMinutes: s.durationMinutes,
              distanceKm: s.distanceKm ?? null,
              steps: s.steps ?? null,
              source,
              externalId: s.externalId,
              dataOrigin: s.dataOrigin ?? null,
              recordingMethod: s.recordingMethod ?? null,
              deviceType: s.device ?? null,
              qualityStatus: needsReview ? "needs_review" : "device_reported",
              createHash: hash,
              notes: needsReview ? "Bertabrakan waktu dengan catatan lain; periksa agar tidak terhitung dua kali." : null,
            },
          });
          await recordAudit(tx, { userId, eventType: "activity_imported", metadata: { recordId: saved.id, source, needsReview } });
          await emitRecordEvent(tx, { userId, kind: "activity", action: "created", recordId: saved.id, revision: saved.version, occurredAt: saved.startedAt, localDates: [localRecordTime(saved.startedAt, timezone).localDate], timezone, source, quality: saved.qualityStatus, provenance: { externalId: s.externalId, dataOrigin: s.dataOrigin ?? null, recordingMethod: s.recordingMethod ?? null, device: s.device ?? null } });
          return { externalId: s.externalId, status: needsReview ? ("CREATED_NEEDS_REVIEW" as const) : ("CREATED" as const), id: saved.id, ...(needsReview ? { reason: "TIME_OVERLAP" } : {}) };
        });
        results.push(outcome);
      } catch (e) {
        // Pengiriman paralel dengan externalId yang sama: baris pemenang sudah ada.
        if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") {
          const existing = await prisma.activitySession.findUnique({ where: { userId_source_externalId: { userId, source, externalId: s.externalId } } });
          results.push({ externalId: s.externalId, status: "DUPLICATE", id: existing?.id });
        } else throw e;
      }
    }
    const count = (st: ImportOutcome["status"]) => results.filter((r) => r.status === st).length;
    return {
      source,
      results,
      summary: { created: count("CREATED"), createdNeedsReview: count("CREATED_NEEDS_REVIEW"), duplicate: count("DUPLICATE"), rejected: count("REJECTED") },
    };
  },
};
