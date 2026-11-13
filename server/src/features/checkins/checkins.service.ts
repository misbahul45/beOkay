import { z } from "zod";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { consentService } from "../consent/consent.service.ts";
import { emitRecordEvent } from "../events/record-events.ts";
import { preferencesService } from "../preferences/preferences.service.ts";

export const ENERGY_LEVELS = ["LOW", "OK", "HIGH"] as const;
export type EnergyLevel = (typeof ENERGY_LEVELS)[number];
export const energySchema = z.object({ energy: z.enum(ENERGY_LEVELS) }).strict();

const view = (r: { localDate: Date; energy: string; version: number; updatedAt: Date } | null) =>
  r ? { localDate: r.localDate.toISOString().slice(0, 10), energy: r.energy as EnergyLevel, version: r.version, updatedAt: r.updatedAt.toISOString() } : null;

export const checkinsService = {
  async today(userId: string, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    const { timezone } = await preferencesService.get(userId);
    const localDate = localRecordTime(now, timezone).localDate;
    const row = await prisma.dailyCheckin.findUnique({ where: { userId_localDate: { userId, localDate: new Date(localDate + "T00:00:00Z") } } });
    return { localDate, checkin: view(row) };
  },

  async energyToday(userId: string, now = new Date()): Promise<EnergyLevel | null> {
    const { timezone } = await preferencesService.get(userId);
    const localDate = localRecordTime(now, timezone).localDate;
    const row = await prisma.dailyCheckin.findUnique({ where: { userId_localDate: { userId, localDate: new Date(localDate + "T00:00:00Z") } }, select: { energy: true } });
    return (row?.energy as EnergyLevel | undefined) ?? null;
  },

  async setEnergy(userId: string, energy: EnergyLevel, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    const { timezone } = await preferencesService.get(userId);
    const localDate = localRecordTime(now, timezone).localDate;
    const row = await prisma.$transaction(async (tx) => {
      const key = { userId_localDate: { userId, localDate: new Date(localDate + "T00:00:00Z") } };
      const old = await tx.dailyCheckin.findUnique({ where: key });
      if (old?.energy === energy) return old;
      const saved = old
        ? await tx.dailyCheckin.update({ where: key, data: { energy, version: { increment: 1 } } })
        : await tx.dailyCheckin.create({ data: { userId, localDate: new Date(localDate + "T00:00:00Z"), energy } });
      await recordAudit(tx, { userId, eventType: "energy_checkin_recorded", metadata: { localDate } });
      await emitRecordEvent(tx, { userId, kind: "energy_checkin", action: old ? "corrected" : "created", recordId: saved.id, revision: saved.version, occurredAt: now, localDates: [localDate], timezone, source: "manual", quality: "user_reported" });
      return saved;
    });
    return { localDate, checkin: view(row) };
  },
};
