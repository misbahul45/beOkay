import { expect, test } from "bun:test";
import {
  activityCreateSchema,
  activityPatchSchema,
} from "../../src/features/activity/activity.schema.ts";
import {
  activityEnd,
  activityWeek,
  summarizeActivities,
} from "../../src/features/activity/activity.model.ts";

test("Activity validates completed sessions and derives consistent end", () => {
  const input = {
    id: crypto.randomUUID(),
    activityType: "walking",
    startedAt: "2026-01-01T12:00:00Z",
    durationMinutes: 30,
  };
  expect(activityEnd(input.startedAt, 30).toISOString()).toBe(
    "2026-01-01T12:30:00.000Z",
  );
  expect(activityCreateSchema.parse(input).distanceKm).toBeNull();
  for (const patch of [
    { durationMinutes: 0 },
    { durationMinutes: 1.5 },
    { durationMinutes: 1441 },
    { distanceKm: -1 },
    { steps: 1.5 },
    { reportedIntensity: "inferred" },
    { source: "wearable" },
    { startedAt: "2026-02-30T12:00:00Z" },
    { startedAt: new Date().toISOString(), durationMinutes: 60 },
    { endedAt: "2026-01-01T12:45:00Z" },
  ])
    expect(activityCreateSchema.safeParse({ ...input, ...patch }).success).toBe(
      false,
    );
  expect(
    activityPatchSchema.parse({
      expectedVersion: 1,
      reason: "archive",
      archived: true,
    }),
  ).toEqual({ expectedVersion: 1, reason: "archive", archived: true });
});
test("Activity optional totals preserve unknown, explicit zero, review exclusion and partial coverage", () => {
  expect(summarizeActivities([]).durationMinutes).toBeNull();
  const total = summarizeActivities([
    {
      durationMinutes: 30,
      distanceKm: 2.5,
      steps: 0,
      qualityStatus: "user_reported",
    },
    {
      durationMinutes: 15,
      distanceKm: null,
      steps: null,
      qualityStatus: "user_reported",
    },
    {
      durationMinutes: 60,
      distanceKm: 10,
      steps: 100,
      qualityStatus: "needs_review",
    },
  ]);
  expect(total.count).toBe(3);
  expect(total.eligibleCount).toBe(2);
  expect(total.reviewCount).toBe(1);
  expect(total.durationMinutes).toBe(45);
  expect(total.distanceKm).toEqual({
    value: 2.5,
    knownSessions: 1,
    totalSessions: 2,
    coverage: "PARTIAL",
  });
  expect(total.steps.value).toBe(0);
});
test("Activity weeks follow locale calendar dates including DST rather than fixed UTC durations", () => {
  expect(activityWeek("2026-03-11", "id-ID")).toEqual({
    startDate: "2026-03-08",
    endDate: "2026-03-15",
    firstDay: 7,
  });
  expect(activityWeek("2026-03-11", "en-GB")).toEqual({
    startDate: "2026-03-09",
    endDate: "2026-03-16",
    firstDay: 1,
  });
  expect(activityWeek("2026-01-01", "id-ID").startDate).toBe("2025-12-28");
});
