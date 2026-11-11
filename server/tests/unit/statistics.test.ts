import { describe, expect, it } from "bun:test";
import {
  MIN_FASTING_READINGS,
  MIN_NUTRITION_DAYS,
  NUTRIENTS,
  buildInsightCards,
  buildStatistics,
  median,
  weekdayPattern,
  type StatDay,
} from "../../src/features/insights/statistics.model.ts";

const isoWeekday = (date: string) => new Date(date + "T00:00:00Z").getUTCDay() || 7;
const dateOf = (i: number) => new Date(Date.UTC(2026, 9, 1 + i)).toISOString().slice(0, 10);
const nutrients = (values?: Partial<Record<(typeof NUTRIENTS)[number], number | null>>, known = 1, total = 1) =>
  Object.fromEntries(NUTRIENTS.map((n) => [n, { value: values ? (values[n] ?? null) : null, knownItems: values && values[n] != null ? known : 0, totalItems: values ? total : 0 }])) as StatDay["nutrients"];
const day = (i: number, over: Partial<StatDay> = {}): StatDay => ({
  date: dateOf(i),
  isoWeekday: isoWeekday(dateOf(i)),
  meals: 0,
  nutrients: nutrients(),
  activityMinutes: null,
  activitySessions: 0,
  glucose: [],
  med: { scheduled: 0, taken: 0, skipped: 0 },
  ...over,
});
const blank = (n: number) => Array.from({ length: n }, (_, i) => day(i));
const at = new Date("2026-11-10T12:00:00Z");
const stat = (r: ReturnType<typeof buildStatistics>, id: string) => r.statistics.find((s) => s.id === id)!;

describe("buildStatistics", () => {
  it("an empty history invents nothing: counts are honest, aggregates are INSUFFICIENT_DATA", () => {
    const r = buildStatistics(blank(14), { glucoseUnit: "mg/dL", computedAt: at });
    expect(r.analyticsState).toBe("INSUFFICIENT_DATA");
    expect(r.period).toEqual({ start: dateOf(7), end: dateOf(13), days: 7 });
    expect(r.comparisonPeriod).toEqual({ start: dateOf(0), end: dateOf(6), days: 7 });
    expect(stat(r, "logging.recorded_days").value).toBe(0);
    for (const id of ["nutrition.calories_per_logged_day", "activity.total_minutes", "activity.active_days", "glucose.fasting_median", "medication.confirmed"]) {
      expect(stat(r, id).state).toBe("INSUFFICIENT_DATA");
      expect(stat(r, id).value).toBeNull();
    }
    expect(r.insights).toEqual([]);
    expect(r.series.every((d) => !d.recorded && d.activityMinutes === null && d.nutrients.calories === null)).toBe(true);
  });

  it("every statistic carries its evidence envelope", () => {
    const r = buildStatistics(blank(14), { glucoseUnit: "mg/dL", computedAt: at });
    for (const s of r.statistics) {
      expect(s.range).toEqual(r.period);
      expect(s.analysisVersion).toBe("stats-v1");
      expect(s.computedAt).toBe(at.toISOString());
      expect(typeof s.derivation).toBe("string");
      expect(s.sourceType.length).toBeGreaterThan(0);
      expect(s.limitations.length).toBeGreaterThan(0);
      expect(["OBSERVATION_COUNT", "DESCRIPTIVE_AGGREGATE"]).toContain(s.category);
    }
    expect(r.statistics.some((s) => /time in range|gmi|hba1c|score|skor|adherence|kepatuhan/i.test(s.id + s.label))).toBe(false);
  });

  it("nutrition averages need the minimum number of logged days and report item coverage", () => {
    const all = blank(14);
    all[12] = day(12, { meals: 1, nutrients: nutrients({ calories: 600, carbohydrates: 80, protein: 20, fat: 10, fiber: null }, 2, 3) });
    all[13] = day(13, { meals: 2, nutrients: nutrients({ calories: 400, carbohydrates: 50, protein: 10, fat: 5, fiber: 3 }, 2, 2) });
    let r = buildStatistics(all, { glucoseUnit: "mg/dL", computedAt: at });
    expect(stat(r, "nutrition.logged_days").value).toBe(2);
    expect(stat(r, "nutrition.calories_per_logged_day").state).toBe("INSUFFICIENT_DATA");
    expect(stat(r, "nutrition.calories_per_logged_day").minimumSample).toBe(MIN_NUTRITION_DAYS);
    all[11] = day(11, { meals: 1, nutrients: nutrients({ calories: 500, carbohydrates: 70, protein: 15, fat: 8, fiber: 2 }) });
    r = buildStatistics(all, { glucoseUnit: "mg/dL", computedAt: at });
    const kcal = stat(r, "nutrition.calories_per_logged_day");
    expect(kcal.state).toBe("READY");
    expect(kcal.value).toBe(500);
    expect(kcal.coverage.status).toBe("PARTIAL");
    expect(kcal.detail).toEqual({ knownItems: 5, totalItems: 6 });
    expect(stat(r, "nutrition.fiber_per_logged_day").sampleCount).toBe(2);
    expect(kcal.comparison).toBeNull();
  });

  it("activity: no sessions is not zero activity; comparisons only when both periods have data", () => {
    const all = blank(14);
    all[2] = day(2, { activityMinutes: 30, activitySessions: 1 });
    all[13] = day(13, { activityMinutes: 50, activitySessions: 2 });
    all[10] = day(10, { activityMinutes: 20, activitySessions: 1 });
    const r = buildStatistics(all, { glucoseUnit: "mg/dL", computedAt: at });
    const total = stat(r, "activity.total_minutes");
    expect(total.value).toBe(70);
    expect(total.comparison).toEqual({ value: 30, range: r.comparisonPeriod, change: 40, direction: "UP" });
    expect(stat(r, "activity.active_days").value).toBe(2);
    expect(stat(r, "activity.minutes_per_active_day").value).toBe(35);
    const only = blank(14);
    only[13] = day(13, { activityMinutes: 25, activitySessions: 1 });
    const r2 = buildStatistics(only, { glucoseUnit: "mg/dL", computedAt: at });
    expect(stat(r2, "activity.total_minutes").comparison).toBeNull();
    expect(stat(r2, "activity.minutes_per_active_day").state).toBe("INSUFFICIENT_DATA");
  });

  it("glucose: fasting median uses only the fasting context and needs enough readings; ranges stay descriptive", () => {
    const all = blank(14);
    const fast = (v: number) => ({ value: v, context: "fasting" });
    all[8] = day(8, { glucose: [fast(120), { value: 190, context: "after_meal" }] });
    all[9] = day(9, { glucose: [fast(130)] });
    let r = buildStatistics(all, { glucoseUnit: "mg/dL", computedAt: at });
    expect(stat(r, "glucose.fasting_median").state).toBe("INSUFFICIENT_DATA");
    expect(stat(r, "glucose.fasting_median").minimumSample).toBe(MIN_FASTING_READINGS);
    all[10] = day(10, { glucose: [fast(124)] });
    r = buildStatistics(all, { glucoseUnit: "mg/dL", computedAt: at });
    expect(stat(r, "glucose.fasting_median").value).toBe(124);
    expect(stat(r, "glucose.readings").value).toBe(4);
    expect(stat(r, "glucose.observed_range").detail).toEqual({ min: 120, max: 190 });
    expect(stat(r, "glucose.fasting_median").limitations.join(" ")).toContain("Time in Range");
    const mmol = buildStatistics(all, { glucoseUnit: "mmol/L", computedAt: at });
    expect(stat(mmol, "glucose.fasting_median").unit).toBe("mmol/L");
  });

  it("medication: unconfirmed is reported as unconfirmed, never as missed or adherence", () => {
    const all = blank(14);
    all[12] = day(12, { med: { scheduled: 2, taken: 1, skipped: 0 } });
    all[13] = day(13, { med: { scheduled: 2, taken: 0, skipped: 1 } });
    const r = buildStatistics(all, { glucoseUnit: "mg/dL", computedAt: at });
    const m = stat(r, "medication.confirmed");
    expect(m.value).toBe(2);
    expect(m.detail).toEqual({ scheduled: 4, taken: 1, skipped: 1, unconfirmed: 2 });
    expect(m.limitations).toContain("Belum dikonfirmasi tidak berarti terlewat.");
    expect(r.insights.find((c) => c.code === "MEDICATION_UNCONFIRMED")?.title).toBe("2 jadwal obat belum dikonfirmasi pada periode ini.");
  });

  it("rejects an odd or empty list of days", () => {
    expect(() => buildStatistics(blank(7), { glucoseUnit: "mg/dL", computedAt: at })).toThrow();
    expect(() => buildStatistics([], { glucoseUnit: "mg/dL", computedAt: at })).toThrow();
  });
});

describe("insight cards", () => {
  it("activity change needs a comparison and at least a 10% difference; lower periods suggest, never shame", () => {
    const all = blank(14);
    all[1] = day(1, { activityMinutes: 100, activitySessions: 1 });
    all[12] = day(12, { activityMinutes: 95, activitySessions: 1 });
    let r = buildStatistics(all, { glucoseUnit: "mg/dL", computedAt: at });
    expect(r.insights.some((c) => c.code === "ACTIVITY_PERIOD_CHANGE")).toBe(false);
    all[12] = day(12, { activityMinutes: 60, activitySessions: 1 });
    r = buildStatistics(all, { glucoseUnit: "mg/dL", computedAt: at });
    const card = r.insights.find((c) => c.code === "ACTIVITY_PERIOD_CHANGE")!;
    expect(card.title).toContain("lebih rendah");
    expect(card.actions).toContain("CREATE_GOAL");
    expect(card.evidence.map((e) => e.label)).toEqual(["7 hari ini", "7 hari sebelumnya"]);
    expect(card.rulesVersion).toBe("insight-rules-v1");
    expect(/gagal|buruk|malas/i.test(card.title + card.body)).toBe(false);
  });

  it("weekday pattern needs 14 days, enough active days and a clear difference", () => {
    const cur = Array.from({ length: 14 }, (_, i) => day(14 + i));
    expect(weekdayPattern(cur)).toBeNull();
    const active = cur.map((d) => (d.isoWeekday <= 5 && Number(d.date.slice(8)) % 2 === 0 ? { ...d, activityMinutes: 20, activitySessions: 1 } : d));
    const p = weekdayPattern(active);
    expect(p?.leaning).toBe("WEEKDAYS");
    expect(weekdayPattern(active.slice(0, 7))).toBeNull();
  });

  it("caps the number of cards", () => {
    const all = blank(14);
    for (let i = 7; i < 14; i++) all[i] = day(i, { med: { scheduled: 1, taken: 0, skipped: 0 }, meals: i === 13 ? 1 : 0, nutrients: i === 13 ? nutrients({ calories: 100 }) : nutrients(), activityMinutes: i % 2 ? 30 : null, activitySessions: i % 2 ? 1 : 0 });
    all[0] = day(0, { activityMinutes: 200, activitySessions: 1 });
    const r = buildStatistics(all, { glucoseUnit: "mg/dL", computedAt: at });
    expect(buildInsightCards(r.statistics, all.slice(7), 1)).toHaveLength(1);
    expect(r.insights.length).toBeLessThanOrEqual(3);
  });

  it("median handles even and odd counts", () => {
    expect(median([])).toBeNull();
    expect(median([3, 1, 2])).toBe(2);
    expect(median([4, 1, 3, 2])).toBe(2.5);
  });
});
