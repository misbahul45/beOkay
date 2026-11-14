import { expect, test } from "bun:test";
import { assessBucket, assessResting, expectedBuckets, freshness, isBucketAligned, summarizeDay, type StoredBucket } from "../../src/features/devices/heart-rate.model.ts";
import { classifyProvenance, provenanceCounts, watchVerification } from "../../src/features/devices/provenance.ts";
import { assessHeartRate, summarize } from "../../src/features/devices/quality.model.ts";
import { assertSimulationAllowed, simulationAllowed } from "../../src/features/devices/simulation.ts";
import { AppError } from "../../src/shared/errors/app-error.ts";

const aligned = (min: number) => new Date(Date.UTC(2026, 10, 14, 1, min, 0));
const stored = (min: number, lo: number, hi: number, avg: number, n: number, origin = "com.example.src", status = "device_reported"): StoredBucket => ({ bucketStart: aligned(min), bpmMin: lo, bpmMax: hi, bpmAvg: avg, sampleCount: n, dataOrigin: origin, qualityStatus: status });

test("bucket: rentang teknis ditolak, nilai tidak lazim hanya ditandai", () => {
  expect(assessBucket({ bucketStart: aligned(5), bpmMin: 60, bpmMax: 90, bpmAvg: 70, sampleCount: 4 })).toEqual({ ok: true, flags: [], status: "device_reported" });
  expect(assessBucket({ bucketStart: aligned(5), bpmMin: 12, bpmMax: 90, bpmAvg: 70, sampleCount: 4 })).toEqual({ ok: false, reason: "HEART_RATE_OUT_OF_DOMAIN" });
  expect(assessBucket({ bucketStart: aligned(5), bpmMin: 60, bpmMax: 400, bpmAvg: 70, sampleCount: 4 })).toEqual({ ok: false, reason: "HEART_RATE_OUT_OF_DOMAIN" });
  expect(assessBucket({ bucketStart: aligned(5), bpmMin: 80, bpmMax: 90, bpmAvg: 70, sampleCount: 4 })).toEqual({ ok: false, reason: "BUCKET_INCONSISTENT" });
  expect(assessBucket({ bucketStart: aligned(5), bpmMin: 60, bpmMax: 90, bpmAvg: 70, sampleCount: 0 })).toEqual({ ok: false, reason: "SAMPLE_COUNT_INVALID" });
  expect(assessBucket({ bucketStart: new Date(aligned(5).getTime() + 1000), bpmMin: 60, bpmMax: 90, bpmAvg: 70, sampleCount: 1 })).toEqual({ ok: false, reason: "BUCKET_NOT_ALIGNED" });
  expect(assessBucket({ bucketStart: aligned(5), bpmMin: 60, bpmMax: 230, bpmAvg: 100, sampleCount: 2 })).toEqual({ ok: true, flags: ["UNUSUAL_VALUE"], status: "needs_review" });
  expect(assessBucket({ bucketStart: aligned(5), bpmMin: Number.NaN, bpmMax: 90, bpmAvg: 70, sampleCount: 2 })).toMatchObject({ ok: false });
  expect(isBucketAligned(aligned(10))).toBe(true);
  expect(isBucketAligned(aligned(7))).toBe(false);
});

test("detak jantung istirahat: domain teknis vs tidak lazim", () => {
  expect(assessResting(62)).toEqual({ ok: true, flags: [], status: "device_reported" });
  expect(assessResting(15)).toMatchObject({ ok: false, reason: "HEART_RATE_OUT_OF_DOMAIN" });
  expect(assessResting(150)).toEqual({ ok: true, flags: ["UNUSUAL_VALUE"], status: "needs_review" });
});

test("ringkasan harian: rata-rata berbobot sampel, tidak cukup data = null, tidak ada interpolasi", () => {
  const day = summarizeDay("2026-11-14", [stored(0, 60, 80, 70, 4), stored(5, 70, 100, 90, 2)], [], 288);
  expect(day).toMatchObject({ observedBuckets: 2, sampleCount: 6, minimum: 60, maximum: 100, average: 76.7, insufficient: false, restingHeartRate: null });
  expect(day.coverage).toBe(0.01);
  const sparse = summarizeDay("2026-11-14", [stored(0, 60, 80, 70, 2)], [], 288);
  expect(sparse).toMatchObject({ insufficient: true, minimum: null, maximum: null, average: null, sampleCount: 2 });
  const none = summarizeDay("2026-11-14", [], [], 288);
  expect(none).toMatchObject({ observedBuckets: 0, sampleCount: 0, minimum: null, average: null, lastMeasurementAt: null, coverage: 0 });
  const withResting = summarizeDay("2026-11-14", [], [{ measuredAt: aligned(0), bpm: 58, dataOrigin: "a", qualityStatus: "device_reported" }, { measuredAt: aligned(30), bpm: 61, dataOrigin: "a", qualityStatus: "needs_review" }], 288);
  expect(withResting).toMatchObject({ restingHeartRate: 61, needsReview: true });
});

test("cakupan harian: hari berjalan memakai menit berlalu, hari depan nol", () => {
  expect(expectedBuckets("2026-11-13", "2026-11-14", 600)).toBe(288);
  expect(expectedBuckets("2026-11-14", "2026-11-14", 600)).toBe(120);
  expect(expectedBuckets("2026-11-15", "2026-11-14", 600)).toBe(0);
  expect(freshness(null, new Date())).toBe("NO_DATA");
  expect(freshness(new Date(Date.now() - 3600_000), new Date())).toBe("FRESH");
  expect(freshness(new Date(Date.now() - 72 * 3600_000), new Date())).toBe("STALE");
});

test("provenans: jam tangan hanya bila metadata perangkat menyatakannya; simulasi dan input manual dipisah", () => {
  expect(classifyProvenance({ source: "health_connect", deviceType: "watch" })).toBe("WATCH_RECORDED");
  expect(classifyProvenance({ source: "health_connect", deviceType: "phone" })).toBe("PHONE_RECORDED");
  expect(classifyProvenance({ source: "health_connect", deviceType: "ring" })).toBe("OTHER_DEVICE");
  expect(classifyProvenance({ source: "health_connect", deviceType: "watch", recordingMethod: "manual" })).toBe("USER_ENTERED");
  expect(classifyProvenance({ source: "health_connect" })).toBe("UNKNOWN");
  expect(classifyProvenance({ source: "health_connect", deviceType: "unknown" })).toBe("UNKNOWN");
  expect(classifyProvenance({ source: "simulated", deviceType: "watch" })).toBe("SIMULATED");
  expect(watchVerification([{ source: "health_connect", dataOrigin: "com.samsung.android.wear.shealth" } as any])).toBe("WATCH_NOT_VERIFIED");
  expect(watchVerification([{ source: "health_connect", deviceType: "watch" }])).toBe("WATCH_SOURCE_DETECTED");
  expect(watchVerification([{ source: "simulated", deviceType: "watch" }])).toBe("WATCH_NOT_VERIFIED");
  expect(provenanceCounts([{ source: "simulated" }, { source: "health_connect", deviceType: "watch" }, { source: "health_connect" }])).toMatchObject({ SIMULATED: 1, WATCH_RECORDED: 1, UNKNOWN: 1 });
});

test("penjaga simulasi: produksi selalu menolak, meski sakelar menyala", () => {
  expect(simulationAllowed({ nodeEnv: "production", enabled: true })).toBe(false);
  expect(simulationAllowed({ nodeEnv: "development", enabled: false })).toBe(false);
  expect(simulationAllowed({ nodeEnv: "development", enabled: true })).toBe(true);
  expect(simulationAllowed({ nodeEnv: "test", enabled: true })).toBe(true);
  expect(() => assertSimulationAllowed(false)).toThrow(AppError);
  try {
    assertSimulationAllowed(false);
  } catch (e) {
    expect(e).toMatchObject({ status: 403, code: "SIMULATION_DISABLED" });
  }
  expect(() => assertSimulationAllowed(true)).not.toThrow();
});

test("kualitas detak jantung: tidak terhubung, tanpa data, sebagian, bendera nilai tidak lazim", () => {
  const ctx = (connected: boolean, lastSyncAt: Date | null = null) => ({ today: "2026-11-14", now: new Date("2026-11-14T10:00:00Z"), connected, lastSyncAt });
  expect(assessHeartRate("2026-11-10", [], ctx(false)).status).toBe("NOT_CONNECTED");
  expect(assessHeartRate("2026-11-10", [], ctx(true, new Date("2026-11-14T09:00:00Z"))).status).toBe("NO_DATA");
  expect(assessHeartRate("2026-11-14", [], ctx(true, null)).status).toBe("STALE");
  const row = { localDate: "2026-11-14", buckets: 3, samples: 9, needsReview: true, dataOrigin: "a", syncedAt: new Date("2026-11-14T09:00:00Z") };
  expect(assessHeartRate("2026-11-14", [row], ctx(true))).toMatchObject({ status: "PARTIAL", value: 9, inference: "OBSERVED", flags: expect.arrayContaining(["DAY_IN_PROGRESS", "UNUSUAL_VALUE"]) });
  expect(assessHeartRate("2026-11-13", [{ ...row, localDate: "2026-11-13", needsReview: false }, { ...row, localDate: "2026-11-13", dataOrigin: "b", needsReview: false }], ctx(true))).toMatchObject({ status: "OK", flags: ["MULTIPLE_ORIGINS"] });
  const days = ["2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13"].map((d) => assessHeartRate(d, d === "2026-11-12" ? [] : [{ ...row, localDate: d, needsReview: false }], ctx(true, new Date("2026-11-14T09:00:00Z"))));
  expect(summarize("heart_rate", days)).toMatchObject({ days: 4, observedDays: 3, coverage: 0.75, reliable: true });
});
