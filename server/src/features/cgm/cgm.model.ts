export const CGM_SUMMARY_VERSION = "cgm-summary-v1";
export const CGM_BANDS = { veryLow: 54, low: 70, high: 180, veryHigh: 250 } as const;
export const READINGS_PER_DAY = 96;
export const SUFFICIENT_COVERAGE = 70;

type Reading = { measuredAt: Date; valueMgDl: number; kind: string };
const r1 = (v: number) => Math.round(v * 10) / 10;

export function summarizeCgm(readings: Reading[], days: number) {
  const historic = readings.filter((r) => r.kind === "HISTORIC");
  const used = historic.length ? historic : readings.filter((r) => r.kind === "SCAN");
  const kindUsed = historic.length ? "HISTORIC" : used.length ? "SCAN" : null;
  if (!used.length) return { kindUsed, readings: 0, coveragePct: 0, sufficient: false, meanMgDl: null, cvPct: null, bands: null };
  const n = used.length;
  const values = used.map((r) => r.valueMgDl);
  const pct = (f: (v: number) => boolean) => r1((values.filter(f).length / n) * 100);
  const mean = values.reduce((s, v) => s + v, 0) / n;
  const sd = Math.sqrt(values.reduce((s, v) => s + (v - mean) ** 2, 0) / n);
  const coveragePct = kindUsed === "HISTORIC" ? Math.min(100, r1((n / (days * READINGS_PER_DAY)) * 100)) : null;
  return {
    kindUsed,
    readings: n,
    coveragePct,
    sufficient: coveragePct !== null && coveragePct >= SUFFICIENT_COVERAGE,
    meanMgDl: r1(mean),
    cvPct: n >= 2 ? r1((sd / mean) * 100) : null,
    bands: {
      veryLow: pct((v) => v < CGM_BANDS.veryLow),
      low: pct((v) => v >= CGM_BANDS.veryLow && v < CGM_BANDS.low),
      inRange: pct((v) => v >= CGM_BANDS.low && v <= CGM_BANDS.high),
      high: pct((v) => v > CGM_BANDS.high && v <= CGM_BANDS.veryHigh),
      veryHigh: pct((v) => v > CGM_BANDS.veryHigh),
    },
  };
}
