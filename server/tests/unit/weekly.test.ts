import { expect, test } from "bun:test";
import { summarizeWeek, type WeekDay } from "../../src/features/insights/weekly.model.ts";

const day = (date: string, p: Partial<WeekDay> = {}): WeekDay => ({
  date, mealCount: 0, glucoseCount: 0, activityMinutes: null,
  medication: { scheduled: 0, taken: 0, skipped: 0, unknown: 0 }, ...p,
});
const week = (over: Record<number, Partial<WeekDay>> = {}) =>
  Array.from({ length: 7 }, (_, i) => day(`2026-11-0${i + 2}`, over[i]));

test("empty week is UNKNOWN / insufficient, never zero activity", () => {
  const s = summarizeWeek(week());
  expect(s).toMatchObject({ recordedDays: 0, coverageStatus: "UNKNOWN", analyticsState: "INSUFFICIENT_DATA" });
  expect(s.activity.totalMinutes).toBeNull();
  expect(s.medication.coverageStatus).toBe("NO_SCHEDULE");
});

test("partial week counts recorded days per domain and keeps unconfirmed medication separate", () => {
  const s = summarizeWeek(week({
    0: { mealCount: 2, activityMinutes: 30, medication: { scheduled: 1, taken: 1, skipped: 0, unknown: 0 } },
    2: { glucoseCount: 3, medication: { scheduled: 1, taken: 0, skipped: 0, unknown: 1 } },
  }));
  expect(s).toMatchObject({ recordedDays: 2, coverageStatus: "PARTIAL", analyticsState: "READY" });
  expect(s.meals).toEqual({ total: 2, daysWithRecords: 1 });
  expect(s.glucose).toEqual({ total: 3, daysWithRecords: 1 });
  expect(s.activity).toEqual({ totalMinutes: 30, daysWithRecords: 1 });
  expect(s.medication).toMatchObject({ scheduled: 2, taken: 1, unconfirmed: 1, coverageStatus: "PARTIAL" });
  expect(JSON.stringify(s)).not.toMatch(/adherence|kepatuhan|average|mean/i);
});
