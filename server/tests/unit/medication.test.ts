import { expect, test } from "bun:test";
import { isoWeekday, occurrencesFor, summarizeOccurrences, validTimezone, zonedToUtc } from "../../src/features/medication/medication.model.ts";
import { intakeCreateSchema, regimenCreateSchema, scheduleCreateSchema } from "../../src/features/medication/medication.schema.ts";

test("local schedule times convert per zone and survive DST", () => {
  expect(zonedToUtc("2026-11-09", "08:00", "Asia/Jakarta").toISOString()).toBe("2026-11-09T01:00:00.000Z");
  // New York: EST (UTC-5) before, EDT (UTC-4) after the 2026-03-08 spring-forward: same wall time, different UTC hour.
  expect(zonedToUtc("2026-03-07", "09:00", "America/New_York").toISOString()).toBe("2026-03-07T14:00:00.000Z");
  expect(zonedToUtc("2026-03-09", "09:00", "America/New_York").toISOString()).toBe("2026-03-09T13:00:00.000Z");
});
test("weekday is ISO (Monday=1, Sunday=7)", () => {
  expect(isoWeekday("2026-11-09")).toBe(1);
  expect(isoWeekday("2026-11-15")).toBe(7);
});
test("occurrences respect weekdays, enabled state and effective date; nothing is assumed taken", () => {
  const base = { regimenId: "r", timezone: "Asia/Jakarta", effectiveFrom: new Date("2026-11-01T00:00:00Z") };
  const schedules = [
    { ...base, id: "a", localTime: "20:00", daysOfWeek: [1, 3], enabled: true },
    { ...base, id: "b", localTime: "07:30", daysOfWeek: [1], enabled: true },
    { ...base, id: "off", localTime: "09:00", daysOfWeek: [1], enabled: false },
    { ...base, id: "future", localTime: "10:00", daysOfWeek: [1], enabled: true, effectiveFrom: new Date("2026-12-01T00:00:00Z") },
    { ...base, id: "tue", localTime: "10:00", daysOfWeek: [2], enabled: true },
  ];
  const occ = occurrencesFor("2026-11-09", schedules);
  expect(occ.map((o) => o.scheduleId)).toEqual(["b", "a"]);
  const summary = summarizeOccurrences(occ.map(() => ({ status: "unknown" as const })));
  expect(summary).toMatchObject({ scheduled: 2, taken: 0, skipped: 0, unknown: 2, coverageStatus: "UNKNOWN" });
  expect(summarizeOccurrences([{ status: "taken" }, { status: "unknown" }]).coverageStatus).toBe("PARTIAL");
  expect(summarizeOccurrences([]).coverageStatus).toBe("NO_SCHEDULE");
});
test("input validation gives actionable rejections", () => {
  expect(validTimezone("Asia/Jakarta")).toBe(true);
  expect(validTimezone("Mars/Base")).toBe(false);
  const id = crypto.randomUUID();
  expect(regimenCreateSchema.safeParse({ id, name: "  " }).success).toBe(false);
  expect(regimenCreateSchema.safeParse({ id, name: "Obat uji", startDate: "2026-02-02", endDate: "2026-01-01" }).success).toBe(false);
  expect(scheduleCreateSchema.safeParse({ id, localTime: "25:00", timezone: "Asia/Jakarta", daysOfWeek: [1], effectiveFrom: "2026-11-01" }).success).toBe(false);
  expect(scheduleCreateSchema.safeParse({ id, localTime: "08:00", timezone: "Asia/Jakarta", daysOfWeek: [1, 1], effectiveFrom: "2026-11-01" }).success).toBe(false);
  expect(intakeCreateSchema.safeParse({ id, status: "taken", scheduleId: id }).success).toBe(false);
  expect(intakeCreateSchema.safeParse({ id, status: "unknown" }).success).toBe(true);
});
