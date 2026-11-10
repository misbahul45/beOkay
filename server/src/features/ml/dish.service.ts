import { Prisma } from "../../generated/prisma/client.ts";
import { env } from "../../config/env.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { logEvent } from "../../shared/http/logger.ts";
import { consentService } from "../consent/consent.service.ts";
import { createModalClient, type ModalClient } from "./modal.client.ts";

export const DISH_MODEL_KEY = "dish-classifier";
/** Perkiraan hanya ditampilkan bila probabilitas terkalibrasi ≥ ambang. Di bawahnya model dianggap tidak yakin dan tidak menampilkan apa pun. */
export const HINT_THRESHOLD = 0.85;
/** JPEG 8x8 putih, hanya untuk memanaskan kontainer Modal; bukan data pengguna. */
const WARMUP_JPEG = Uint8Array.from(Buffer.from("/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkzODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxlZ2P/2wBDARESEhgVGC8aGi9jQjhCY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2P/wAARCAAIAAgDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD0CiiigD//2Q==", "base64"));
const WARMUP_EVERY_MS = 60_000;
const lastWarmup = new Map<string, number>();

/**
 * Tata kelola penggunaan model:
 *  - APPROVED  → boleh dipakai pada hasil pengguna (mode LIVE);
 *  - RESEARCH_ONLY / SHADOW → hanya mode BAYANGAN: dijalankan untuk evaluasi, dicatat, dan TIDAK dikembalikan ke pengguna;
 *  - selain itu / tidak ada model → tidak dijalankan.
 * Bayangan hanya untuk pengguna yang memberi persetujuan `model_inference`; tanpa itu foto tidak dikirim ke Modal.
 */
export function createDishService(client: ModalClient) {
  async function current() {
    return prisma.modelVersion.findFirst({ where: { modelKey: DISH_MODEL_KEY, status: { in: ["APPROVED", "SHADOW", "RESEARCH_ONLY"] } }, orderBy: [{ status: "asc" }, { createdAt: "desc" }] });
  }
  const audit = (userId: string, modelVersionId: string, mode: "SHADOW" | "LIVE", status: string, latencyMs: number, inputBytes: number, top?: { label: string; probability: number }) =>
    prisma.mlInferenceRun.create({ data: { userId, modelVersionId, mode, status, latencyMs: Math.min(latencyMs, 2_000_000), inputBytes, topLabel: top?.label, topProbability: top ? new Prisma.Decimal(top.probability.toFixed(4)) : undefined } });

  return {
    configured: client.configured,

    /** Katalog kemampuan yang jujur: apa yang ada, statusnya, dan apakah boleh dipakai pengguna. */
    async capabilities() {
      const rows = await prisma.modelVersion.findMany({ orderBy: [{ modelKey: "asc" }, { createdAt: "desc" }] });
      return {
        serving: { configured: client.configured, circuitOpen: client.circuitOpen },
        models: rows.map((m) => ({ modelKey: m.modelKey, version: m.version, status: m.status, usableForUsers: m.status === "APPROVED", approvedAt: m.approvedAt?.toISOString() ?? null, approvalNote: m.approvalNote, intendedUse: m.intendedUse, trainingDataProvenance: m.trainingDataProvenance, artifactSha256: m.artifactSha256, evaluation: m.evaluation })),
      };
    },

    /** Dipanggil di latar belakang setelah jalur utama. Tidak pernah melempar; tidak pernah mengubah respons pengguna. */
    async shadow(userId: string, bytes: Uint8Array): Promise<{ ran: boolean; reason?: string }> {
      try {
        if (!client.configured) return { ran: false, reason: "NOT_CONFIGURED" };
        const model = await current();
        if (!model) return { ran: false, reason: "NO_MODEL" };
        try {
          await consentService.requireConsent(userId, "model_inference");
        } catch {
          return { ran: false, reason: "NO_CONSENT" }; // tidak ada pengiriman dan tidak ada catatan
        }
        const mode = model.status === "APPROVED" ? "LIVE" : "SHADOW";
        const r = await client.predict(bytes, 3);
        if (!r.ok) {
          await audit(userId, model.id, mode, r.code === "NOT_CONFIGURED" ? "UNAVAILABLE" : r.code, r.latencyMs, bytes.length);
          return { ran: true, reason: r.code };
        }
        // Versi dan hash artefak yang menjawab harus sama dengan yang terdaftar.
        if (r.data.modelKey !== model.modelKey || r.data.modelVersion !== model.version || r.data.artifactSha256 !== model.artifactSha256) {
          await audit(userId, model.id, mode, "VERSION_MISMATCH", r.latencyMs, bytes.length);
          return { ran: true, reason: "VERSION_MISMATCH" };
        }
        const top = r.data.predictions.reduce((a, b) => (b.probability > a.probability ? b : a));
        await audit(userId, model.id, mode, "OK", r.latencyMs, bytes.length, top);
        return { ran: true };
      } catch (e) {
        logEvent("error", "ml_shadow_failed", { name: e instanceof Error ? e.name : "unknown" });
        return { ran: false, reason: "ERROR" };
      }
    },

    /**
     * Pemanasan kontainer Modal sebelum foto dikirim (cold start ≈ 10 dtk). Hanya bila model APPROVED dan pengguna menyetujui model_inference;
     * memakai gambar putih 1x1, bukan data pengguna; paling sering sekali per menit per pengguna. Tidak pernah melempar.
     */
    async warmup(userId: string): Promise<{ started: boolean; reason?: string }> {
      try {
        const model = await current();
        if (!model || model.status !== "APPROVED") return { started: false, reason: "NOT_APPROVED" };
        if (!client.configured) return { started: false, reason: "NOT_CONFIGURED" };
        await consentService.requireConsent(userId, "model_inference");
        const now = Date.now();
        if (now - (lastWarmup.get(userId) ?? 0) < WARMUP_EVERY_MS) return { started: false, reason: "RECENT" };
        lastWarmup.set(userId, now);
        void client.predict(WARMUP_JPEG, 1).catch(() => {});
        return { started: true };
      } catch {
        return { started: false, reason: "NO_CONSENT_OR_ERROR" };
      }
    },

    /**
     * Satu pintu untuk jalur foto. Model APPROVED + persetujuan model_inference → mode LIVE dan mengembalikan PERKIRAAN (bukan catatan) bila
     * keyakinan terkalibrasi ≥ ambang; kegagalan apa pun → null sehingga pengguna tetap mendapat hasil deterministik/Mistral (tidak pernah galat).
     * Model non-APPROVED → hanya bayangan, mengembalikan null.
     */
    async assist(userId: string, bytes: Uint8Array): Promise<{ label: string; probability: number; modelVersion: string } | null> {
      try {
        const model = await current();
        if (!model || model.status !== "APPROVED") {
          await this.shadow(userId, bytes);
          return null;
        }
        try {
          await consentService.requireConsent(userId, "model_inference");
        } catch {
          return null;
        }
        if (!client.configured) return null;
        const r = await client.predict(bytes, 3);
        if (!r.ok) {
          await audit(userId, model.id, "LIVE", r.code === "NOT_CONFIGURED" ? "UNAVAILABLE" : r.code, r.latencyMs, bytes.length);
          return null;
        }
        if (r.data.modelKey !== model.modelKey || r.data.modelVersion !== model.version || r.data.artifactSha256 !== model.artifactSha256) {
          await audit(userId, model.id, "LIVE", "VERSION_MISMATCH", r.latencyMs, bytes.length);
          return null;
        }
        const top = r.data.predictions.reduce((a, b) => (b.probability > a.probability ? b : a));
        await audit(userId, model.id, "LIVE", "OK", r.latencyMs, bytes.length, top);
        return top.probability >= HINT_THRESHOLD ? { label: top.label, probability: top.probability, modelVersion: model.version } : null;
      } catch (e) {
        logEvent("error", "ml_assist_failed", { name: e instanceof Error ? e.name : "unknown" });
        return null;
      }
    },

    /** Hasil untuk pengguna: hanya dari model APPROVED. Selain itu null (pemanggil memakai jalur deterministik/lain). */
    async liveRecommendation(bytes: Uint8Array) {
      const model = await current();
      if (!model || model.status !== "APPROVED" || !client.configured) return null;
      const r = await client.predict(bytes, 3);
      if (!r.ok || r.data.artifactSha256 !== model.artifactSha256 || r.data.modelVersion !== model.version) return null;
      return { modelVersion: model.version, predictions: r.data.predictions };
    },
  };
}

export const dishService = createDishService(createModalClient({ url: env.MODAL_ML_URL, token: env.MODAL_ML_AUTH_TOKEN }));
