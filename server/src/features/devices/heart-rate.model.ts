export const HR_BUCKET_MINUTES = 5;
export const HR_BUCKET_MS = HR_BUCKET_MINUTES * 60_000;
export const HR_DOMAIN_MIN = 20;
export const HR_DOMAIN_MAX = 300;
export const HR_UNUSUAL_LOW = 30;
export const HR_UNUSUAL_HIGH = 220;
export const RESTING_UNUSUAL_LOW = 30;
export const RESTING_UNUSUAL_HIGH = 140;
export const MIN_SAMPLES_FOR_SUMMARY = 3;
export const HR_METHODOLOGY = "Rata-rata sampel yang teramati (bukan rata-rata berbobot waktu). Sampel dikelompokkan per 5 menit; tidak ada interpolasi.";

export type HeartRateFlag = "UNUSUAL_VALUE";
export type BucketInput = { bucketStart: Date; bpmMin: number; bpmMax: number; bpmAvg: number; sampleCount: number };
export type BucketAssessment = { ok: true; flags: HeartRateFlag[]; status: "device_reported" | "needs_review" } | { ok: false; reason: string };

export const isBucketAligned = (d: Date) => Number.isFinite(d.getTime()) && d.getTime() % HR_BUCKET_MS === 0;
export const round2 = (n: number) => Math.round(n * 100) / 100;
const inDomain = (n: number) => Number.isFinite(n) && n >= HR_DOMAIN_MIN && n <= HR_DOMAIN_MAX;

export function assessBucket(b: BucketInput): BucketAssessment {
  if (!isBucketAligned(b.bucketStart)) return { ok: false, reason: "BUCKET_NOT_ALIGNED" };
  if (!Number.isInteger(b.sampleCount) || b.sampleCount < 1) return { ok: false, reason: "SAMPLE_COUNT_INVALID" };
  if (![b.bpmMin, b.bpmMax, b.bpmAvg].every(inDomain)) return { ok: false, reason: "HEART_RATE_OUT_OF_DOMAIN" };
  if (!(b.bpmMin <= b.bpmAvg && b.bpmAvg <= b.bpmMax)) return { ok: false, reason: "BUCKET_INCONSISTENT" };
  const unusual = b.bpmMin < HR_UNUSUAL_LOW || b.bpmMax > HR_UNUSUAL_HIGH;
  return { ok: true, flags: unusual ? ["UNUSUAL_VALUE"] : [], status: unusual ? "needs_review" : "device_reported" };
}

export function assessResting(bpm: number): BucketAssessment {
  if (!inDomain(bpm)) return { ok: false, reason: "HEART_RATE_OUT_OF_DOMAIN" };
  const unusual = bpm < RESTING_UNUSUAL_LOW || bpm > RESTING_UNUSUAL_HIGH;
  return { ok: true, flags: unusual ? ["UNUSUAL_VALUE"] : [], status: unusual ? "needs_review" : "device_reported" };
}

export type StoredBucket = { bucketStart: Date; bpmMin: number; bpmMax: number; bpmAvg: number; sampleCount: number; dataOrigin: string; qualityStatus: string };
export type StoredResting = { measuredAt: Date; bpm: number; dataOrigin: string | null; qualityStatus: string };

export type DayHeartRate = {
  date: string;
  observedBuckets: number;
  sampleCount: number;
  coverage: number;
  minimum: number | null;
  maximum: number | null;
  average: number | null;
  restingHeartRate: number | null;
  lastMeasurementAt: string | null;
  needsReview: boolean;
  origins: string[];
  insufficient: boolean;
};

export function expectedBuckets(date: string, today: string, nowMinutesOfDay: number) {
  if (date > today) return 0;
  if (date < today) return (24 * 60) / HR_BUCKET_MINUTES;
  return Math.max(1, Math.ceil(nowMinutesOfDay / HR_BUCKET_MINUTES));
}

export function summarizeDay(date: string, buckets: StoredBucket[], resting: StoredResting[], expected: number): DayHeartRate {
  const samples = buckets.reduce((s, b) => s + b.sampleCount, 0);
  const insufficient = samples < MIN_SAMPLES_FOR_SUMMARY;
  const last = buckets.reduce<StoredBucket | null>((m, b) => (!m || b.bucketStart > m.bucketStart ? b : m), null);
  const latestResting = resting.reduce<StoredResting | null>((m, r) => (!m || r.measuredAt > m.measuredAt ? r : m), null);
  const weighted = samples ? buckets.reduce((s, b) => s + b.bpmAvg * b.sampleCount, 0) / samples : null;
  return {
    date,
    observedBuckets: buckets.length,
    sampleCount: samples,
    coverage: expected > 0 ? Math.min(1, round2(buckets.length / expected)) : 0,
    minimum: insufficient ? null : Math.min(...buckets.map((b) => b.bpmMin)),
    maximum: insufficient ? null : Math.max(...buckets.map((b) => b.bpmMax)),
    average: insufficient || weighted === null ? null : Math.round(weighted * 10) / 10,
    restingHeartRate: latestResting ? latestResting.bpm : null,
    lastMeasurementAt: last ? last.bucketStart.toISOString() : null,
    needsReview: buckets.some((b) => b.qualityStatus === "needs_review") || resting.some((r) => r.qualityStatus === "needs_review"),
    origins: [...new Set([...buckets.map((b) => b.dataOrigin), ...resting.map((r) => r.dataOrigin ?? "unknown")])].sort(),
    insufficient,
  };
}

export function freshness(lastAt: Date | null, now: Date, staleAfterHours = 48): "NO_DATA" | "FRESH" | "STALE" {
  if (!lastAt) return "NO_DATA";
  return now.getTime() - lastAt.getTime() > staleAfterHours * 3_600_000 ? "STALE" : "FRESH";
}
