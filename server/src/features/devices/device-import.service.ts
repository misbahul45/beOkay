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
import { assessBucket, assessResting, round2 } from "./heart-rate.model.ts";
import { assertSimulationAllowed, SIMULATED_SOURCE, simulationAllowed } from "./simulation.ts";

export type Outcome = { externalId: string; status: "CREATED" | "UPDATED" | "DUPLICATE" | "UNCHANGED" | "REJECTED"; id?: string; reason?: string; needsReview?: boolean };
type Prefs = { workouts: boolean; steps: boolean; weight: boolean; glucose: boolean; sleep: boolean; heartRate: boolean; restingHeartRate: boolean };
type ImportOptions = { simulationAllowed?: boolean };

const isUnique = (e: unknown) => e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002";
const sha = (v: unknown) => createHash("sha256").update(JSON.stringify(v)).digest("hex");
const DAY = 86_400_000;
export const DEVICE_PREF_DEFAULTS: Prefs = { workouts: false, steps: false, weight: false, glucose: false, sleep: false, heartRate: false, restingHeartRate: false };

function prefView(row: (Prefs & { updatedAt?: Date }) | null) {
  const v = row ?? DEVICE_PREF_DEFAULTS;
  return { workouts: v.workouts, steps: v.steps, weight: v.weight, glucose: v.glucose, sleep: v.sleep, heartRate: v.heartRate, restingHeartRate: v.restingHeartRate, updatedAt: row?.updatedAt?.toISOString() ?? null };
}

const count = (list: Outcome[], st: Outcome["status"]) => list.filter((o) => o.status === st).length;
const domainResult = (list: Outcome[]) => ({
  results: list,
  created: count(list, "CREATED"),
  updated: count(list, "UPDATED"),
  duplicate: count(list, "DUPLICATE"),
  unchanged: count(list, "UNCHANGED"),
  rejected: count(list, "REJECTED"),
  needsReview: list.filter((o) => o.needsReview).length,
});
const rejectAll = <T extends { externalId?: string; localDate?: string; bucketStart?: string }>(items: T[], reason: string): Outcome[] => items.map((i) => ({ externalId: i.externalId ?? i.localDate ?? i.bucketStart ?? "", status: "REJECTED", reason }));

type BucketWrite = { dataOrigin: string; bucketStart: Date; bpmMin: number; bpmMax: number; bpmAvg: number; sampleCount: number; recordingMethod: string | null; deviceType: string | null; status: string; flags: string[]; key: string; index: number };
type RestingWrite = { externalId: string; dataOrigin: string | null; measuredAt: Date; bpm: number; recordingMethod: string | null; deviceType: string | null; status: string; flags: string[] };

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

  async import(userId: string, input: DeviceImportInput, now = new Date(), options: ImportOptions = {}) {
    await consentService.requireConsent(userId, "health_data_processing");
    const source = input.source;
    const simulated = source === SIMULATED_SOURCE;
    if (simulated) assertSimulationAllowed(options.simulationAllowed ?? simulationAllowed());
    const prefs = await this.preferences(userId);
    const { timezone } = await preferencesService.get(userId);

    const steps = await this.importSteps(userId, source, input.steps, prefs.steps, timezone, now);
    const weights = simulated && input.weights.length ? rejectAll(input.weights, "SIMULATED_NOT_SUPPORTED") : await this.importWeights(userId, source, input.weights, prefs.weight, timezone);
    const glucose = simulated && input.glucose.length ? rejectAll(input.glucose, "SIMULATED_NOT_SUPPORTED") : await this.importGlucose(userId, source, input.glucose, prefs.glucose, timezone);
    const sleep = await this.importSleep(userId, source, input.sleep, prefs.sleep, timezone, now);
    const heartRate = await this.importHeartRate(userId, source, input.heartRate, prefs.heartRate, timezone, now);
    const restingHeartRate = await this.importResting(userId, source, input.restingHeartRate, prefs.restingHeartRate, timezone, now);

    const created = steps.upserted + count(weights, "CREATED") + count(glucose, "CREATED") + count(sleep, "CREATED") + count(heartRate, "CREATED") + count(restingHeartRate, "CREATED");
    const changed = created + count(sleep, "UPDATED") + count(heartRate, "UPDATED") + count(restingHeartRate, "UPDATED");
    if (changed)
      await emitDomainEvent(prisma, {
        userId,
        type: "device.imported",
        dedupeKey: `device-import:${userId}:${now.getTime()}:${sha({ steps, w: weights.length, g: glucose.length, s: sleep.length, h: heartRate.length, r: restingHeartRate.length })}`,
        payload: { source, steps: steps.upserted, weights: count(weights, "CREATED"), glucose: count(glucose, "CREATED"), sleep: count(sleep, "CREATED"), heartRate: count(heartRate, "CREATED") + count(heartRate, "UPDATED"), restingHeartRate: count(restingHeartRate, "CREATED") + count(restingHeartRate, "UPDATED") },
        source,
        occurredAt: now,
        timezone,
        quality: "device_reported",
      });
    return {
      source,
      simulated,
      preferences: prefs,
      steps,
      weights: domainResult(weights),
      glucose: domainResult(glucose),
      sleep: domainResult(sleep),
      heartRate: domainResult(heartRate),
      restingHeartRate: domainResult(restingHeartRate),
    };
  },

  async importSteps(userId: string, source: string, items: DeviceImportInput["steps"], enabled: boolean, timezone: string, now: Date) {
    const steps = { upserted: 0, unchanged: 0, rejected: 0 };
    if (items.length && !enabled) {
      steps.rejected = items.length;
      return steps;
    }
    const today = localRecordTime(now, timezone).localDate;
    for (const s of items) {
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
    return steps;
  },

  async importWeights(userId: string, source: string, items: DeviceImportInput["weights"], enabled: boolean, timezone: string) {
    if (items.length && !enabled) return rejectAll(items, "DEVICE_TYPE_DISABLED");
    const out: Outcome[] = [];
    for (const w of items) {
      try {
        const existing = await prisma.vitalMeasurement.findUnique({ where: { userId_source_externalId: { userId, source, externalId: w.externalId } } });
        if (existing) {
          out.push({ externalId: w.externalId, status: "DUPLICATE", id: existing.id });
          continue;
        }
        const saved = await prisma.$transaction(async (tx) => {
          const row = await tx.vitalMeasurement.create({ data: { userId, kind: "weight", value: Math.round(w.kg * 1000) / 1000, unit: "kg", measuredAt: new Date(w.measuredAt), source, externalId: w.externalId, createHash: sha({ source, ...w }) } });
          await recordAudit(tx, { userId, eventType: "vital_recorded", metadata: { recordId: row.id, kind: "weight", source } });
          await emitRecordEvent(tx, { userId, kind: "vital", action: "created", recordId: row.id, revision: 1, occurredAt: row.measuredAt, localDates: [localRecordTime(row.measuredAt, timezone).localDate], timezone, source, quality: "device_reported", provenance: { externalId: w.externalId, dataOrigin: w.dataOrigin ?? null } });
          return row;
        });
        out.push({ externalId: w.externalId, status: "CREATED", id: saved.id });
      } catch (e) {
        if (!isUnique(e)) throw e;
        out.push({ externalId: w.externalId, status: "DUPLICATE" });
      }
    }
    return out;
  },

  async importGlucose(userId: string, source: string, items: DeviceImportInput["glucose"], enabled: boolean, timezone: string) {
    if (items.length && !enabled) return rejectAll(items, "DEVICE_TYPE_DISABLED");
    const out: Outcome[] = [];
    for (const g of items) {
      const mgdl = canonicalGlucose(g.value, g.unit);
      if (mgdl.lt(1) || mgdl.gt(2000)) {
        out.push({ externalId: g.externalId, status: "REJECTED", reason: "GLUCOSE_VALUE_OUT_OF_DOMAIN" });
        continue;
      }
      try {
        const existing = await prisma.glucoseObservation.findUnique({ where: { userId_source_sourceRecordId: { userId, source, sourceRecordId: g.externalId } } });
        if (existing) {
          out.push({ externalId: g.externalId, status: "DUPLICATE", id: existing.id });
          continue;
        }
        const saved = await prisma.$transaction(async (tx) => {
          const row = await tx.glucoseObservation.create({ data: { userId, originalValue: g.value, originalUnit: g.unit, valueMgDl: mgdl, measuredAt: new Date(g.measuredAt), mealContext: g.mealContext, source, sourceRecordId: g.externalId, measurementType: g.specimen, qualityStatus: "device_reported", qualityFlags: [], createHash: sha({ source, ...g }) } });
          await recordAudit(tx, { userId, eventType: "glucose_recorded", metadata: { recordId: row.id, source } });
          await emitRecordEvent(tx, { userId, kind: "glucose", action: "created", recordId: row.id, revision: 1, occurredAt: row.measuredAt, localDates: [localRecordTime(row.measuredAt, timezone).localDate], timezone, source, quality: "device_reported", provenance: { externalId: g.externalId, dataOrigin: g.dataOrigin ?? null } });
          return row;
        });
        out.push({ externalId: g.externalId, status: "CREATED", id: saved.id });
      } catch (e) {
        if (!isUnique(e)) throw e;
        out.push({ externalId: g.externalId, status: "DUPLICATE" });
      }
    }
    return out;
  },

  async importSleep(userId: string, source: string, items: DeviceImportInput["sleep"], enabled: boolean, timezone: string, now: Date) {
    if (items.length && !enabled) return rejectAll(items, "DEVICE_TYPE_DISABLED");
    const out: Outcome[] = [];
    for (const s of items) {
      const start = new Date(s.startedAt), end = new Date(s.endedAt);
      const minutes = Math.round((end.getTime() - start.getTime()) / 60_000);
      if (minutes < 1 || minutes > 1440) {
        out.push({ externalId: s.externalId, status: "REJECTED", reason: "SLEEP_DURATION_OUT_OF_RANGE" });
        continue;
      }
      const provenance = { dataOrigin: s.dataOrigin ?? null, recordingMethod: s.recordingMethod ?? null, deviceType: s.device ?? null };
      try {
        const existing = await prisma.sleepSession.findUnique({ where: { userId_source_externalId: { userId, source, externalId: s.externalId } } });
        if (existing && existing.startedAt.getTime() === start.getTime() && existing.endedAt.getTime() === end.getTime()) {
          out.push({ externalId: s.externalId, status: "DUPLICATE", id: existing.id });
          continue;
        }
        const row = await prisma.$transaction(async (tx) => {
          const saved = existing
            ? await tx.sleepSession.update({ where: { id: existing.id }, data: { startedAt: start, endedAt: end, durationMinutes: minutes, ...provenance, updatedAt: now } })
            : await tx.sleepSession.create({ data: { userId, startedAt: start, endedAt: end, durationMinutes: minutes, source, externalId: s.externalId, ...provenance } });
          const dates = [localRecordTime(end, timezone).localDate, ...(existing ? [localRecordTime(existing.endedAt, timezone).localDate] : [])];
          await emitRecordEvent(tx, { userId, kind: "sleep", action: existing ? "corrected" : "created", recordId: saved.id, revision: existing ? Math.floor(now.getTime() / 1000) : 1, occurredAt: end, localDates: dates, timezone, source, quality: "device_reported", provenance: { externalId: s.externalId, ...provenance } });
          return saved;
        });
        out.push({ externalId: s.externalId, status: existing ? "UPDATED" : "CREATED", id: row.id });
      } catch (e) {
        if (!isUnique(e)) throw e;
        out.push({ externalId: s.externalId, status: "DUPLICATE" });
      }
    }
    if (out.some((o) => o.status === "CREATED" || o.status === "UPDATED")) await recordAudit(prisma, { userId, eventType: "sleep_imported", metadata: { source, sessions: out.filter((o) => o.status === "CREATED" || o.status === "UPDATED").length } });
    return out;
  },

  async importHeartRate(userId: string, source: string, items: DeviceImportInput["heartRate"], enabled: boolean, timezone: string, now: Date) {
    if (items.length && !enabled) return rejectAll(items, "DEVICE_TYPE_DISABLED");
    if (!items.length) return [];
    const out: Outcome[] = new Array(items.length);
    const candidates: BucketWrite[] = [];
    items.forEach((b, index) => {
      const bucketStart = new Date(b.bucketStart);
      const label = b.bucketStart;
      const a = assessBucket({ bucketStart, bpmMin: b.bpmMin, bpmMax: b.bpmMax, bpmAvg: b.bpmAvg, sampleCount: b.sampleCount });
      if (!a.ok) {
        out[index] = { externalId: label, status: "REJECTED", reason: a.reason };
        return;
      }
      const dataOrigin = b.dataOrigin ?? "unknown";
      candidates.push({ dataOrigin, bucketStart, bpmMin: Math.round(b.bpmMin), bpmMax: Math.round(b.bpmMax), bpmAvg: round2(b.bpmAvg), sampleCount: b.sampleCount, recordingMethod: b.recordingMethod ?? null, deviceType: b.device ?? null, status: a.status, flags: a.flags, key: `${dataOrigin}|${bucketStart.getTime()}`, index });
    });
    if (candidates.length) {
      const stored = await prisma.wearableHeartRateBucket.findMany({
        where: { userId, source, bucketStart: { in: candidates.map((c) => c.bucketStart) } },
        select: { id: true, dataOrigin: true, bucketStart: true, bpmMin: true, bpmMax: true, bpmAvg: true, sampleCount: true },
      });
      const state = new Map(stored.map((r) => [`${r.dataOrigin}|${r.bucketStart.getTime()}`, { bpmMin: r.bpmMin, bpmMax: r.bpmMax, bpmAvg: r.bpmAvg.toNumber(), sampleCount: r.sampleCount, id: r.id as string | null }]));
      const writes = new Map<string, BucketWrite>();
      for (const c of candidates) {
        const prev = state.get(c.key);
        const label = c.bucketStart.toISOString();
        if (prev && prev.bpmMin === c.bpmMin && prev.bpmMax === c.bpmMax && prev.bpmAvg === c.bpmAvg && prev.sampleCount === c.sampleCount) {
          out[c.index] = { externalId: label, status: "DUPLICATE", ...(prev.id ? { id: prev.id } : {}) };
          continue;
        }
        if (prev && prev.sampleCount > c.sampleCount) {
          out[c.index] = { externalId: label, status: "UNCHANGED", reason: "OLDER_REVISION", ...(prev.id ? { id: prev.id } : {}) };
          continue;
        }
        const earlier = writes.get(c.key);
        if (earlier) out[earlier.index] = { externalId: label, status: "DUPLICATE", reason: "SUPERSEDED_IN_REQUEST" };
        writes.set(c.key, c);
        state.set(c.key, { bpmMin: c.bpmMin, bpmMax: c.bpmMax, bpmAvg: c.bpmAvg, sampleCount: c.sampleCount, id: prev?.id ?? null });
        out[c.index] = { externalId: label, status: prev?.id ? "UPDATED" : "CREATED", needsReview: c.status === "needs_review" };
      }
      const toWrite = [...writes.values()];
      if (toWrite.length) {
        const rows = toWrite.map((r) => Prisma.sql`(${userId}::uuid, ${source}, ${r.dataOrigin}, ${r.bucketStart}::timestamptz, ${r.bpmMin}::int, ${r.bpmMax}::int, ${r.bpmAvg}::numeric, ${r.sampleCount}::int, ${r.recordingMethod}::text, ${r.deviceType}::text, ${r.status}, ${r.flags}::text[])`);
        const written = await prisma.$transaction(async (tx) => {
          const returned = await tx.$queryRaw<{ id: string; inserted: boolean; bucket_start: Date; data_origin: string }[]>`
            INSERT INTO wearable_heart_rate_buckets (user_id, source, data_origin, bucket_start, bpm_min, bpm_max, bpm_avg, sample_count, recording_method, device_type, quality_status, quality_flags)
            VALUES ${Prisma.join(rows)}
            ON CONFLICT (user_id, source, data_origin, bucket_start) DO UPDATE SET
              bpm_min = EXCLUDED.bpm_min, bpm_max = EXCLUDED.bpm_max, bpm_avg = EXCLUDED.bpm_avg, sample_count = EXCLUDED.sample_count,
              recording_method = EXCLUDED.recording_method, device_type = EXCLUDED.device_type, quality_status = EXCLUDED.quality_status,
              quality_flags = EXCLUDED.quality_flags, updated_at = ${now}
            RETURNING id, (xmax = 0) AS inserted, bucket_start, data_origin`;
          const firstInserted = returned.find((r) => r.inserted);
          const lead = firstInserted ?? returned[0];
          if (lead) {
            const dates = [...new Set(returned.map((r) => localRecordTime(r.bucket_start, timezone).localDate))];
            const latest = new Date(Math.max(...returned.map((r) => r.bucket_start.getTime())));
            await emitRecordEvent(tx, { userId, kind: "heart_rate", action: firstInserted ? "created" : "corrected", recordId: lead.id, revision: firstInserted ? 1 : Math.floor(now.getTime() / 1000), occurredAt: latest, localDates: dates, timezone, source, quality: "device_reported", provenance: { buckets: returned.length } });
            await recordAudit(tx, { userId, eventType: "heart_rate_imported", metadata: { source, buckets: returned.length } });
          }
          return returned;
        });
        const ids = new Map(written.map((r) => [`${r.data_origin}|${r.bucket_start.getTime()}`, r.id]));
        for (const w of toWrite) {
          const o = out[w.index];
          const id = ids.get(w.key);
          if (o && id) o.id = id;
        }
      }
    }
    return out;
  },

  async importResting(userId: string, source: string, items: DeviceImportInput["restingHeartRate"], enabled: boolean, timezone: string, now: Date) {
    if (items.length && !enabled) return rejectAll(items, "DEVICE_TYPE_DISABLED");
    if (!items.length) return [];
    const out: Outcome[] = new Array(items.length);
    const stored = await prisma.wearableRestingHeartRate.findMany({ where: { userId, source, externalId: { in: items.map((i) => i.externalId) } }, select: { id: true, externalId: true, bpm: true, measuredAt: true } });
    const state = new Map(stored.map((r) => [r.externalId, { bpm: r.bpm, at: r.measuredAt.getTime(), id: r.id as string | null }]));
    const writes = new Map<string, RestingWrite & { index: number }>();
    items.forEach((r, index) => {
      const measuredAt = new Date(r.measuredAt);
      const a = assessResting(r.bpm);
      if (!a.ok) {
        out[index] = { externalId: r.externalId, status: "REJECTED", reason: a.reason };
        return;
      }
      const bpm = Math.round(r.bpm);
      const prev = state.get(r.externalId);
      if (prev && prev.bpm === bpm && prev.at === measuredAt.getTime()) {
        out[index] = { externalId: r.externalId, status: "DUPLICATE", ...(prev.id ? { id: prev.id } : {}) };
        return;
      }
      const earlier = writes.get(r.externalId);
      if (earlier) out[earlier.index] = { externalId: r.externalId, status: "DUPLICATE", reason: "SUPERSEDED_IN_REQUEST" };
      writes.set(r.externalId, { externalId: r.externalId, dataOrigin: r.dataOrigin ?? null, measuredAt, bpm, recordingMethod: r.recordingMethod ?? null, deviceType: r.device ?? null, status: a.status, flags: a.flags, index });
      state.set(r.externalId, { bpm, at: measuredAt.getTime(), id: prev?.id ?? null });
      out[index] = { externalId: r.externalId, status: prev?.id ? "UPDATED" : "CREATED", needsReview: a.status === "needs_review" };
    });
    const toWrite = [...writes.values()];
    if (toWrite.length) {
      const rows = toWrite.map((r) => Prisma.sql`(${userId}::uuid, ${source}, ${r.dataOrigin}::text, ${r.externalId}, ${r.measuredAt}::timestamptz, ${r.bpm}::int, ${r.recordingMethod}::text, ${r.deviceType}::text, ${r.status}, ${r.flags}::text[])`);
      await prisma.$transaction(async (tx) => {
        const returned = await tx.$queryRaw<{ id: string; inserted: boolean; external_id: string; measured_at: Date }[]>`
          INSERT INTO wearable_resting_heart_rates (user_id, source, data_origin, external_id, measured_at, bpm, recording_method, device_type, quality_status, quality_flags)
          VALUES ${Prisma.join(rows)}
          ON CONFLICT (user_id, source, external_id) DO UPDATE SET
            data_origin = EXCLUDED.data_origin, measured_at = EXCLUDED.measured_at, bpm = EXCLUDED.bpm, recording_method = EXCLUDED.recording_method,
            device_type = EXCLUDED.device_type, quality_status = EXCLUDED.quality_status, quality_flags = EXCLUDED.quality_flags, updated_at = ${now}
          RETURNING id, (xmax = 0) AS inserted, external_id, measured_at`;
        const firstInserted = returned.find((r) => r.inserted);
        const lead = firstInserted ?? returned[0];
        if (lead) {
          const dates = [...new Set(returned.map((r) => localRecordTime(r.measured_at, timezone).localDate))];
          const latest = new Date(Math.max(...returned.map((r) => r.measured_at.getTime())));
          await emitRecordEvent(tx, { userId, kind: "heart_rate", action: firstInserted ? "created" : "corrected", recordId: lead.id, revision: firstInserted ? 1 : Math.floor(now.getTime() / 1000), occurredAt: latest, localDates: dates, timezone, source, quality: "device_reported", provenance: { resting: returned.length } });
          await recordAudit(tx, { userId, eventType: "heart_rate_imported", metadata: { source, resting: returned.length } });
        }
        for (const r of returned) {
          const w = writes.get(r.external_id);
          const o = w ? out[w.index] : undefined;
          if (o) o.id = r.id;
        }
      });
    }
    return out;
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
      return { date, steps: r ? r.steps : null, source: r?.source ?? null, dataOrigin: r?.dataOrigin ?? null, simulated: r?.source === SIMULATED_SOURCE };
    });
    const values = series.map((s) => s.steps).filter((v): v is number => v !== null);
    const lastRow = rows.at(-1);
    return { timezone, days, series, daysWithData: values.length, medianSteps: median(values), latest: lastRow ? { date: lastRow.localDate.toISOString().slice(0, 10), steps: lastRow.steps, syncedAt: lastRow.syncedAt.toISOString(), simulated: lastRow.source === SIMULATED_SOURCE } : null, source: "health_connect" };
  },

  async sleepSummary(userId: string, days: number, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    const rows = await prisma.sleepSession.findMany({ where: { userId, endedAt: { gte: new Date(now.getTime() - days * DAY) } }, orderBy: { startedAt: "desc" } });
    const durations = rows.map((r) => r.durationMinutes);
    return { days, sessions: rows.map((r) => ({ id: r.id, startedAt: r.startedAt.toISOString(), endedAt: r.endedAt.toISOString(), durationMinutes: r.durationMinutes, source: r.source, dataOrigin: r.dataOrigin, deviceType: r.deviceType, simulated: r.source === SIMULATED_SOURCE })), medianMinutes: median(durations), notice: "Durasi dari perangkat, tanpa penilaian kualitas tidur." };
  },
};
