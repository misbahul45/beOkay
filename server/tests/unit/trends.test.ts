import { describe, expect, it } from "bun:test";
import { buildTrends, type DayInput } from "../../src/features/insights/trends.model.ts";

const day = (i: number, over: Partial<DayInput> = {}): DayInput => ({
  date: `2026-11-${String(i).padStart(2, "0")}`,
  glucose: [],
  activityMinutes: null,
  mealCount: 0,
  carbs: null,
  medTaken: 0,
  medSkipped: 0,
  ...over,
});
const blank = (n: number, from = 1) => Array.from({ length: n }, (_, i) => day(from + i));

describe("buildTrends", () => {
  it("empty history is INSUFFICIENT_DATA; nothing is invented as zero", () => {
    const t = buildTrends(blank(14));
    expect(t.analyticsState).toBe("INSUFFICIENT_DATA");
    expect(t.series.length).toBe(7);
    expect(t.series.every((d) => d.glucose === null && d.activityMinutes === null && !d.recorded)).toBe(true);
    expect(t.activity.totalMinutes).toBeNull();
    expect(t.glucose.min).toBeNull();
    expect(t.notes).toEqual([]);
  });

  it("glucose per day keeps min/max/count only; no judgement fields", () => {
    const all = blank(14);
    all[13] = day(14, { glucose: [110, 95.55, 180] });
    const t = buildTrends(all);
    expect(t.series[6]!.glucose).toEqual({ count: 3, min: 95.55, max: 180 });
    expect(t.glucose).toMatchObject({ readings: 3, daysWithReadings: 1, min: 95.6, max: 180 });
    expect(JSON.stringify(t)).not.toMatch(/inRange|target|score|adherence|average|mean/i);
  });

  it("streak counts back from yesterday when today is still empty; best streak is within the period", () => {
    const all = blank(14);
    for (const i of [9, 10, 11, 12, 13]) all[i] = day(i + 1, { mealCount: 1 }); // 10..14 → recorded; index 13 (day 14 = today) also recorded
    all[13] = day(14); // today empty
    const t = buildTrends(all);
    expect(t.consistency.currentStreak).toBe(4); // days 10-13
    expect(t.consistency.bestStreak).toBe(4);
    expect(t.notes).toContainEqual({ code: "STREAK", days: 4 });
  });

  it("a gap breaks the streak (but history stays visible)", () => {
    const all = blank(14);
    for (const i of [7, 8, 10, 11, 12, 13]) all[i] = day(i + 1, { activityMinutes: 20 });
    const t = buildTrends(all);
    expect(t.consistency.currentStreak).toBe(4);
    expect(t.consistency.bestStreak).toBe(4);
  });

  it("activity comparison appears only when both periods have data, and only notes an increase", () => {
    const up = blank(14);
    up[2] = day(3, { activityMinutes: 30 });
    up[9] = day(10, { activityMinutes: 50 });
    const t = buildTrends(up);
    expect(t.activity).toMatchObject({ totalMinutes: 50, previousTotalMinutes: 30, activeDays: 1 });
    expect(t.previous).toHaveLength(7);
    expect(t.previous[2]).toEqual({ date: "2026-11-03", activityMinutes: 30 });
    expect(t.previous[0]!.activityMinutes).toBeNull();
    expect(t.notes).toContainEqual({ code: "ACTIVITY_MORE", current: 50, previous: 30 });
    expect(t.notes).toContainEqual({ code: "ACTIVITY_PERSONAL_BEST_DAY", date: "2026-11-10", minutes: 50 });

    const down = blank(14);
    down[2] = day(3, { activityMinutes: 80 });
    down[9] = day(10, { activityMinutes: 20 });
    expect(buildTrends(down).notes.some((n) => n.code === "ACTIVITY_MORE")).toBe(false);

    const noPrev = blank(14);
    noPrev[9] = day(10, { activityMinutes: 40 });
    const t3 = buildTrends(noPrev);
    expect(t3.activity.previousTotalMinutes).toBeNull(); // unknown ≠ 0, so no "more than before" claim
    expect(t3.notes.some((n) => n.code === "ACTIVITY_MORE" || n.code === "ACTIVITY_PERSONAL_BEST_DAY")).toBe(false);
  });

  it("more recorded days than the previous period is noted; fewer is silent", () => {
    const all = blank(14);
    all[0] = day(1, { mealCount: 1 });
    for (const i of [8, 9, 10]) all[i] = day(i + 1, { mealCount: 1 });
    expect(buildTrends(all).notes).toContainEqual({ code: "MORE_DAYS_RECORDED", current: 3, previous: 1 });
    const fewer = blank(14);
    for (const i of [0, 1, 2]) fewer[i] = day(i + 1, { mealCount: 1 });
    fewer[9] = day(10, { mealCount: 1 });
    expect(buildTrends(fewer).notes.some((n) => n.code === "MORE_DAYS_RECORDED")).toBe(false);
  });

  it("rejects odd-length input", () => {
    expect(() => buildTrends(blank(13))).toThrow();
  });
});
