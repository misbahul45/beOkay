import { prisma } from "../../infrastructure/database/prisma.ts";
import { consentService } from "../consent/consent.service.ts";
import type { SyncCheckpointInput } from "./device-import.schema.ts";
import { assertSimulationAllowed, SIMULATED_SOURCE } from "./simulation.ts";

export const syncCheckpointService = {
  async report(userId: string, input: SyncCheckpointInput, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    if (input.source === SIMULATED_SOURCE) assertSimulationAllowed();
    const patch =
      input.outcome === "success"
        ? { lastAttemptAt: now, lastSuccessAt: now, lastErrorCode: null, ...(input.cursor ? { cursor: input.cursor } : {}) }
        : input.outcome === "failure"
          ? { lastAttemptAt: now, lastErrorCode: input.errorCode ?? "UNKNOWN" }
          : { lastAttemptAt: now };
    const row = await prisma.deviceSyncCheckpoint.upsert({
      where: { userId_source_metric: { userId, source: input.source, metric: input.metric } },
      create: { userId, source: input.source, metric: input.metric, cursor: input.cursor ?? null, ...patch },
      update: patch,
    });
    return view(row);
  },

  async list(userId: string) {
    await consentService.requireConsent(userId, "health_data_processing");
    const rows = await prisma.deviceSyncCheckpoint.findMany({ where: { userId }, orderBy: [{ source: "asc" }, { metric: "asc" }] });
    return { checkpoints: rows.map(view) };
  },
};

const view = (r: { source: string; metric: string; cursor: string | null; lastAttemptAt: Date | null; lastSuccessAt: Date | null; lastErrorCode: string | null }) => ({
  source: r.source,
  metric: r.metric,
  cursor: r.cursor,
  lastAttemptAt: r.lastAttemptAt?.toISOString() ?? null,
  lastSuccessAt: r.lastSuccessAt?.toISOString() ?? null,
  lastErrorCode: r.lastErrorCode,
});
