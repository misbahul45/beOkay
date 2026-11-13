import { createHash } from "node:crypto";
import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { consentService } from "../consent/consent.service.ts";
import { emitRecordEvent } from "../events/record-events.ts";
import { emitDomainEvent } from "../../infrastructure/queue/events.ts";
import { canonicalGlucose } from "../glucose/glucose.model.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { median } from "../usage/usage.model.ts";
import type { DeviceImportInput, DevicePreferencesInput } from "./device-import.schema.ts";

type Outcome = { externalId: string; status: "CREATED" | "DUPLICATE" | "REJECTED"; id?: string; reason?: string };
const isUnique = (e: unknown) => e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002";
const sha = (v: unknown) => createHash("sha256").update(JSON.stringify(v)).digest("hex");
const DAY = 86_400_000;
export const DEVICE_PREF_DEFAULTS = { workouts: false, steps: false, weight: false, glucose: false, sleep: false };

function prefView(row: { workouts: boolean; steps: boolean; weight: boolean; glucose: boolean; sleep: boolean; updatedAt?: Date } | null) {
  const v = row ?? DEVICE_PREF_DEFAULTS;
  return { workouts: v.workouts, steps: v.steps, weight: v.weight, glucose: v.glucose, sleep: v.sleep, updatedAt: row?.updatedAt?.toISOString() ?? null };
}

export const deviceImportService = {
  async preferences(userId: string) {
    return prefView(await prisma.deviceImportPreference.findUnique({ where: { userId } }));
  },

  async setPreferences(userId: string, input: DevicePreferencesInput) {
    await consentService.requireConsent(userId, "health_data_processing");
    const row = await prisma.$transaction(async (tx) => {
      const saved = await tx.deviceImportPreference.upsert({ where: { userId }, create: { userId, ...DEVICE_PREF_DEFAULTS, ...input }, update: input });
      await recordAudit(tx, { userId, eventType: "device_import_preferences_updated", metadata: input });
      return saved;
    });
    return prefView(row);
  },

  async import(userId: string, input: DeviceImportInput, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    const prefs = await this.preferences(userId);
    const { timezone } = await preferencesService.get(userId);
    const source = input.source;
    const rejectAll = <T extends { externalId?: string; localDate?: string }>(items: T[], reason: string): Outcome[] => items.map((i) => ({ externalId: i.externalId ?? i.localDate ?? "", status: "REJECTED", reason }));

    const steps = { upserted: 0, unchanged: 0, rejected: 0 };
    if (input.steps.length && !prefs.steps) steps.rejected = input.steps.length;
    else {
      const today = localRecordTime(now, timezone).localDate;
      for (const s of input.steps) {
        if (s.localDate > today) {
          steps.rejected++;
          continue;
        }
        const key = { userId_source_localDate: { userId, source, localDate: new Date(s.localDate + "T00:00:00Z") } };
        const old = await prisma.dailySteps.findUnique({ where: key });
        if (old?.steps === s.steps) {
          steps.unchanged++;
          continue;
        }
        await prisma.$transaction(async (tx) => {
          const row = await tx.dailySteps.upsert({ where: key, create: { userId, source, localDate: new Date(s.localDate + "T00:00:00Z"), steps: s.steps, dataOrigin: s.dataOrigin ?? null }, update: { steps: s.steps, syncedAt: now, dataOrigin: s.dataOrigin ?? null } });
          await emitRecordEvent(tx, { userId, kind: "steps", action: old ? "corrected" : "created", recordId: row.id, revision: Math.floor(now.getTime() / 1000), occurredAt: new Date(s.localDate + "T12:00:00Z"), localDates: [s.localDate], timezone, source, quality: "device_reported", provenance: { dataOrigin: s.dataOrigin ?? null } });
        });
        steps.upserted++;
      }
      if (steps.upserted) await recordAudit(prisma, { userId, eventType: "activity_steps_imported", metadata: { source, days: steps.upserted } });
    }

    const weights: Outcome[] = input.weights.length && !prefs.weight ? rejectAll(input.weights, "DEVICE_TYPE_DISABLED") : [];
    if (prefs.weight)
      for (const w of input.weights) {
        try {
          const existing = await prisma.vitalMeasurement.findUnique({ where: { userId_source_externalId: { userId, source, externalId: w.externalId } } });
          if (existing) {
            weights.push({ externalId: w.externalId, status: "DUPLICATE", id: existing.id });
            continue;
          }
          const saved = await prisma.$transaction(async (tx) => {
            const row = await tx.vitalMeasurement.create({ data: { userId, kind: "weight", value: Math.round(w.kg * 1000) / 1000, unit: "kg", measuredAt: new Date(w.measuredAt), source, externalId: w.externalId, createHash: sha({ source, ...w }) } });
            await recordAudit(tx, { userId, eventType: "vital_recorded", metadata: { recordId: row.id, kind: "weight", source } });
            await emitRecordEvent(tx, { userId, kind: "vital", action: "created", recordId: row.id, revision: 1, occurredAt: row.measuredAt, localDates: [localRecordTime(row.measuredAt, timezone).localDate], timezone, source, quality: "device_reported", provenance: { externalId: w.externalId, dataOrigin: w.dataOrigin ?? null } });
            return row;
          });
          weights.push({ externalId: w.externalId, status: "CREATED", id: saved.id });
        } catch (e) {
          if (!isUnique(e)) throw e;
          weights.push({ externalId: w.externalId, status: "DUPLICATE" });
        }
      }

    const glucose: Outcome[] = input.glucose.length && !prefs.glucose ? rejectAll(input.glucose, "DEVICE_TYPE_DISABLED") : [];
    if (prefs.glucose)
      for (const g of input.glucose) {
        const mgdl = canonicalGlucose(g.value, g.unit);
        if (mgdl.lt(1) || mgdl.gt(2000)) {
          glucose.push({ externalId: g.externalId, status: "REJECTED", reason: "GLUCOSE_VALUE_OUT_OF_DOMAIN" });
          continue;
        }
        try {
          const existing = await prisma.glucoseObservation.findUnique({ where: { userId_source_sourceRecordId: { userId, source, sourceRecordId: g.externalId } } });
          if (existing) {
            glucose.push({ externalId: g.externalId, status: "DUPLICATE", id: existing.id });
            continue;
          }
          const saved = await prisma.$transaction(async (tx) => {
            const row = await tx.glucoseObservation.create({ data: { userId, originalValue: g.value, originalUnit: g.unit, valueMgDl: mgdl, measuredAt: new Date(g.measuredAt), mealContext: g.mealContext, source, sourceRecordId: g.externalId, measurementType: g.specimen, qualityStatus: "device_reported", qualityFlags: [], createHash: sha({ source, ...g }) } });
            await recordAudit(tx, { userId, eventType: "glucose_recorded", metadata: { recordId: row.id, source } });
            await emitRecordEvent(tx, { userId, kind: "glucose", action: "created", recordId: row.id, revision: 1, occurredAt: row.measuredAt, localDates: [localRecordTime(row.measuredAt, timezone).localDate], timezone, source, quality: "device_reported", provenance: { externalId: g.externalId, dataOrigin: g.dataOrigin ?? null } });
            return row;
          });
          glucose.push({ externalId: g.externalId, status: "CREATED", id: saved.id });
        } catch (e) {
          if (!isUnique(e)) throw e;
          glucose.push({ externalId: g.externalId, status: "DUPLICATE" });
        }
      }

    const sleep: Outcome[] = input.sleep.length && !prefs.sleep ? rejectAll(input.sleep, "DEVICE_TYPE_DISABLED") : [];
    if (prefs.sleep)
      for (const s of input.sleep) {
        const start = new Date(s.startedAt), end = new Date(s.endedAt);
        const minutes = Math.round((end.getTime() - start.getTime()) / 60_000);
        if (minutes < 1 || minutes > 1440) {
          sleep.push({ externalId: s.externalId, status: "REJECTED", reason: "SLEEP_DURATION_OUT_OF_RANGE" });
          continue;
        }
        try {
          const row = await prisma.$transaction(async (tx) => {
            const saved = await tx.sleepSession.create({ data: { userId, startedAt: start, endedAt: end, durationMinutes: minutes, source, externalId: s.externalId, dataOrigin: s.dataOrigin ?? null } });
            await emitRecordEvent(tx, { userId, kind: "sleep", action: "created", recordId: saved.id, revision: 1, occurredAt: end, localDates: [localRecordTime(end, timezone).localDate], timezone, source, quality: "device_reported", provenance: { externalId: s.externalId, dataOrigin: s.dataOrigin ?? null } });
            return saved;
          });
          sleep.push({ externalId: s.externalId, status: "CREATED", id: row.id });
        } catch (e) {
          if (!isUnique(e)) throw e;
          sleep.push({ externalId: s.externalId, status: "DUPLICATE" });
        }
      }
    if (sleep.some((s) => s.status === "CREATED")) await recordAudit(prisma, { userId, eventType: "sleep_imported", metadata: { source, sessions: sleep.filter((s) => s.status === "CREATED").length } });

    const count = (list: Outcome[], st: Outcome["status"]) => list.filter((o) => o.status === st).length;
    const created = steps.upserted + count(weights, "CREATED") + count(glucose, "CREATED") + count(sleep, "CREATED");
    if (created) await emitDomainEvent(prisma, { userId, type: "device.imported", dedupeKey: `device-import:${userId}:${now.getTime()}:${sha({ steps, w: weights.length, g: glucose.length, s: sleep.length })}`, payload: { source, steps: steps.upserted, weights: count(weights, "CREATED"), glucose: count(glucose, "CREATED"), sleep: count(sleep, "CREATED") }, source, occurredAt: now, timezone, quality: "device_reported" });
    return {
      source,
      preferences: prefs,
      steps,
      weights: { results: weights, created: count(weights, "CREATED"), duplicate: count(weights, "DUPLICATE"), rejected: count(weights, "REJECTED") },
      glucose: { results: glucose, created: count(glucose, "CREATED"), duplicate: count(glucose, "DUPLICATE"), rejected: count(glucose, "REJECTED") },
      sleep: { results: sleep, created: count(sleep, "CREATED"), duplicate: count(sleep, "DUPLICATE"), rejected: count(sleep, "REJECTED") },
    };
  },

  async steps(userId: string, days: number, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    const { timezone } = await preferencesService.get(userId);
    const today = localRecordTime(now, timezone).localDate;
    const from = new Date(Date.parse(today + "T00:00:00Z") - (days - 1) * DAY);
    const rows = await prisma.dailySteps.findMany({ where: { userId, localDate: { gte: from } }, orderBy: { localDate: "asc" } });
    const byDate = new Map(rows.map((r) => [r.localDate.toISOString().slice(0, 10), r]));
    const series = Array.from({ length: days }, (_, i) => {
      const date = new Date(from.getTime() + i * DAY).toISOString().slice(0, 10);
      const r = byDate.get(date);
      return { date, steps: r ? r.steps : null, source: r?.source ?? null };
    });
    const values = series.map((s) => s.steps).filter((v): v is number => v !== null);
    return { timezone, days, series, daysWithData: values.length, medianSteps: median(values), latest: rows.at(-1) ? { date: rows.at(-1)!.localDate.toISOString().slice(0, 10), steps: rows.at(-1)!.steps, syncedAt: rows.at(-1)!.syncedAt.toISOString() } : null, source: "health_connect" };
  },

  async sleepSummary(userId: string, days: number, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    const rows = await prisma.sleepSession.findMany({ where: { userId, endedAt: { gte: new Date(now.getTime() - days * DAY) } }, orderBy: { startedAt: "desc" } });
    const durations = rows.map((r) => r.durationMinutes);
    return { days, sessions: rows.map((r) => ({ id: r.id, startedAt: r.startedAt.toISOString(), endedAt: r.endedAt.toISOString(), durationMinutes: r.durationMinutes, source: r.source })), medianMinutes: median(durations), notice: "Durasi dari perangkat, tanpa penilaian kualitas tidur." };
  },
};
