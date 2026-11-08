import { expect, test } from "bun:test";
import { goalCreateSchema, goalPatchSchema, checkinCreateSchema } from "../../src/features/goals/goals.schema.ts";
import { goalBounds, summarizeGoal } from "../../src/features/goals/goals.model.ts";

test("Goals require explicit behavior targets and correction reasons", () => {
  const input = { id: crypto.randomUUID(), title: "Jalan", goalType: "activity_minutes", targetValue: 30, period: "daily", startDate: "2026-01-01" };
  expect(goalCreateSchema.parse(input).endDate).toBeNull();
  for (const fields of [{ goalType: "glucose_target" }, { targetValue: 0 }, { startDate: "2026-02-30" }, { endDate: "2025-12-31" }, { userId: crypto.randomUUID() }, { targetValue: 1.001 }]) expect(goalCreateSchema.safeParse({ ...input, ...fields }).success).toBeFalse();
  expect(goalPatchSchema.safeParse({ expectedVersion: 1, reason: " " , status: "paused" }).success).toBeFalse();
  expect(goalPatchSchema.safeParse({ expectedVersion: 1, reason: "change" }).success).toBeFalse();
  expect(checkinCreateSchema.parse({ id: crypto.randomUUID(), eventAt: "2026-01-01T00:00:00Z", status: "unknown" }).value).toBe(1);
});
test("Goals use locale calendar weeks and inclusive goal date range", () => {
  expect(goalBounds("2026-03-11", "weekly", "en-GB", "2026-03-10", "2026-03-12")).toEqual({ startDate: "2026-03-09", endDate: "2026-03-16", sourceStartDate: "2026-03-10", sourceEndDate: "2026-03-13" });
  expect(goalBounds("2026-03-11", "daily", "id-ID", "2026-03-12", null).sourceStartDate).toBe("2026-03-12");
});
test("Goal progress preserves missing data and explicit skipped or unknown", () => {
  expect(summarizeGoal("manual_checkins", 2, []).value).toBeNull();
  const result = summarizeGoal("manual_checkins", 2, [{ date: "2026-01-01", status: "completed", value: 1 }, { date: "2026-01-01", status: "skipped", value: 9 }, { date: "2026-01-02", status: "unknown", value: 9 }]);
  expect(result.value).toBe(1);
  expect(result.recordedDays).toBe(2);
  expect(result.unknownCount).toBe(1);
  expect(result.skippedCount).toBe(1);
  expect(result.ratio).toBe(0.5);
  expect(summarizeGoal("record_glucose", 3, [{ date: "2026-01-01" }, { date: "2026-01-01" }, { date: "2026-01-02" }]).value).toBe(2);
  expect(summarizeGoal("activity_minutes", 30, [{ date: "2026-01-01", value: 45 }]).ratio).toBe(1.5);
});
