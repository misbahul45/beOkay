export const FEATURE_SCHEMA_VERSION = "behavior-features-v1";
export const BASELINE_KEY = "behavior-slot-baseline";
export const BASELINE_VERSION = "baseline-v1";
export const SLOTS = ["MORNING", "AFTERNOON", "EVENING"] as const;
export type Slot = (typeof SLOTS)[number];

export const slotOfHour = (h: number): Slot | null => (h >= 5 && h < 11 ? "MORNING" : h >= 11 && h < 17 ? "AFTERNOON" : h >= 17 && h < 22 ? "EVENING" : null);

export type FeatureRow = {
  userId: string;
  localDate: string;
  slot: Slot;
  dayOfWeek: number;
  priorActiveDays7: number;
  priorSlotHits28: number;
  priorObservedDays28: number;
  priorDeliveredInSlot14: number;
  priorUsefulRate: number | null;
  windowEnd: string;
  label: 0 | 1 | null;
  observed: boolean;
};

export type DayEvidence = { localDate: string; slots: Partial<Record<Slot, boolean>>; observed: boolean };

const addDays = (d: string, n: number) => new Date(Date.parse(d + "T00:00:00Z") + n * 86_400_000).toISOString().slice(0, 10);

export function buildFeatures(userId: string, days: DayEvidence[], deliveries: { localDate: string; slot: Slot; useful: boolean | null }[], from: string, to: string): FeatureRow[] {
  const byDate = new Map(days.map((d) => [d.localDate, d]));
  const rows: FeatureRow[] = [];
  for (let d = from; d <= to; d = addDays(d, 1)) {
    const prior = (n: number) => Array.from({ length: n }, (_, i) => byDate.get(addDays(d, -(i + 1)))).filter((x): x is DayEvidence => Boolean(x));
    const p7 = prior(7), p28 = prior(28);
    const today = byDate.get(d);
    for (const slot of SLOTS) {
      const pd = deliveries.filter((x) => x.slot === slot && x.localDate < d && x.localDate >= addDays(d, -14));
      const rated = deliveries.filter((x) => x.localDate < d && x.useful !== null);
      rows.push({
        userId,
        localDate: d,
        slot,
        dayOfWeek: new Date(d + "T00:00:00Z").getUTCDay(),
        priorActiveDays7: p7.filter((x) => Object.values(x.slots).some(Boolean)).length,
        priorSlotHits28: p28.filter((x) => x.slots[slot]).length,
        priorObservedDays28: p28.filter((x) => x.observed).length,
        priorDeliveredInSlot14: pd.length,
        priorUsefulRate: rated.length ? rated.filter((x) => x.useful).length / rated.length : null,
        windowEnd: addDays(d, -1),
        label: today?.observed ? (today.slots[slot] ? 1 : 0) : null,
        observed: Boolean(today?.observed),
      });
    }
  }
  return rows;
}

export const BASELINE_PRIOR = { alpha: 1, beta: 3 };

export function baselineScore(r: Pick<FeatureRow, "priorSlotHits28" | "priorObservedDays28">): number {
  return (r.priorSlotHits28 + BASELINE_PRIOR.alpha) / (r.priorObservedDays28 + BASELINE_PRIOR.alpha + BASELINE_PRIOR.beta);
}

export function bestSlot(rows: FeatureRow[]): { slot: Slot; score: number } | null {
  if (!rows.length) return null;
  return rows.map((r) => ({ slot: r.slot, score: baselineScore(r) })).sort((a, b) => b.score - a.score || SLOTS.indexOf(a.slot) - SLOTS.indexOf(b.slot))[0]!;
}

export type Split = { train: FeatureRow[]; test: FeatureRow[]; testUsers: string[]; cutoff: string };

export function splitByUserAndTime(rows: FeatureRow[], opts: { testUserFraction: number; cutoff: string; seed?: string }): Split {
  const users = [...new Set(rows.map((r) => r.userId))].sort();
  const hash = (s: string) => [...(opts.seed ?? "beokay") + s].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7);
  const testUsers = users.filter((u) => (hash(u) % 1000) / 1000 < opts.testUserFraction);
  const isTest = new Set(testUsers);
  return { train: rows.filter((r) => !isTest.has(r.userId) && r.localDate < opts.cutoff), test: rows.filter((r) => isTest.has(r.userId) && r.localDate >= opts.cutoff), testUsers, cutoff: opts.cutoff };
}

export function leakageProblems(split: Split): string[] {
  const out: string[] = [];
  const trainUsers = new Set(split.train.map((r) => r.userId));
  for (const u of split.testUsers) if (trainUsers.has(u)) out.push(`USER_IN_BOTH:${u}`);
  for (const r of [...split.train, ...split.test]) if (r.windowEnd >= r.localDate) out.push(`FEATURE_WINDOW_NOT_BEFORE_LABEL:${r.userId}:${r.localDate}`);
  if (split.train.some((r) => r.localDate >= split.cutoff)) out.push("TRAIN_AFTER_CUTOFF");
  if (split.test.some((r) => r.localDate < split.cutoff)) out.push("TEST_BEFORE_CUTOFF");
  return out;
}

export function brier(pairs: { p: number; y: 0 | 1 }[]): number | null {
  if (!pairs.length) return null;
  return pairs.reduce((s, x) => s + (x.p - x.y) ** 2, 0) / pairs.length;
}

export function prAuc(pairs: { p: number; y: 0 | 1 }[]): number | null {
  const pos = pairs.filter((x) => x.y === 1).length;
  if (!pos || pos === pairs.length) return null;
  const sorted = [...pairs].sort((a, b) => b.p - a.p);
  let tp = 0, fp = 0, area = 0, prevRecall = 0;
  for (const x of sorted) {
    x.y ? tp++ : fp++;
    const recall = tp / pos, precision = tp / (tp + fp);
    area += (recall - prevRecall) * precision;
    prevRecall = recall;
  }
  return area;
}

export function calibration(pairs: { p: number; y: 0 | 1 }[], bins = 5) {
  const out = Array.from({ length: bins }, (_, i) => ({ lo: i / bins, hi: (i + 1) / bins, n: 0, meanP: 0, rate: 0 }));
  for (const x of pairs) {
    const b = out[Math.min(bins - 1, Math.floor(x.p * bins))]!;
    b.n++;
    b.meanP += x.p;
    b.rate += x.y;
  }
  for (const b of out) if (b.n) { b.meanP /= b.n; b.rate /= b.n; }
  const ece = pairs.length ? out.reduce((s, b) => s + (b.n / pairs.length) * Math.abs(b.meanP - b.rate), 0) : null;
  return { bins: out, ece };
}

export function psi(a: number[], b: number[], bins = 5): number | null {
  if (!a.length || !b.length) return null;
  const hist = (xs: number[]) => {
    const h = Array(bins).fill(0) as number[];
    for (const x of xs) h[Math.min(bins - 1, Math.floor(Math.max(0, Math.min(0.9999, x)) * bins))]!++;
    return h.map((c) => Math.max(c / xs.length, 1e-4));
  };
  const ha = hist(a), hb = hist(b);
  return ha.reduce((s, p, i) => s + (p - hb[i]!) * Math.log(p / hb[i]!), 0);
}

export function evaluate(rows: FeatureRow[], opts: { testUserFraction: number; cutoff: string; seed?: string }) {
  const split = splitByUserAndTime(rows, opts);
  const labelled = (xs: FeatureRow[]) => xs.filter((r): r is FeatureRow & { label: 0 | 1 } => r.label !== null).map((r) => ({ p: baselineScore(r), y: r.label }));
  const test = labelled(split.test), train = labelled(split.train);
  return {
    model: `${BASELINE_KEY}@${BASELINE_VERSION}`,
    featureSchema: FEATURE_SCHEMA_VERSION,
    leakage: leakageProblems(split),
    sizes: { trainRows: split.train.length, testRows: split.test.length, testUsers: split.testUsers.length, labelledTest: test.length },
    missing: { trainUnobservedFraction: split.train.length ? split.train.filter((r) => !r.observed).length / split.train.length : null, testUnobservedFraction: split.test.length ? split.test.filter((r) => !r.observed).length / split.test.length : null },
    brier: brier(test),
    prAuc: prAuc(test),
    calibration: calibration(test),
    drift: { scorePsi: psi(train.map((x) => x.p), test.map((x) => x.p)) },
    claim: "Pipa evaluasi saja. Tanpa data nyata, angka ini bukan kinerja model.",
  };
}
