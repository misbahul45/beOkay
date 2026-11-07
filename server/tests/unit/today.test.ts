import { expect, test } from "bun:test";
import { buildToday } from "../../src/features/today/today.model.ts";

test("Today uses saved timezone across midnight without invented measurements", () => {
  const result = buildToday({ displayName: "Rina", timezone: "Asia/Jakarta", glucoseUnit: "mmol/L" }, new Date("2026-11-08T18:00:00Z"));
  expect(result.date).toBe("2026-11-09");
  expect(result.greeting).toBe("Selamat malam");
  expect(result.glucoseUnit).toBe("mmol/L");
  expect(result.metrics).toHaveLength(4);
  expect(result.metrics.every((metric) => metric.value === null && metric.availability === "NOT_IMPLEMENTED")).toBe(true);
  expect(result.analyticsState).toBe("NOT_AVAILABLE");
  expect(result.generatedAt).toBe("2026-11-08T18:00:00.000Z");
});

test("Today greeting uses local morning and handles a negative UTC offset", () => {
  const instant = new Date("2026-11-09T02:00:00Z");
  expect(buildToday({ displayName: "A", timezone: "Asia/Jakarta", glucoseUnit: "mg/dL" }, instant).greeting).toBe("Selamat pagi");
  const west = buildToday({ displayName: "B", timezone: "America/Los_Angeles", glucoseUnit: "mg/dL" }, instant);
  expect(west.date).toBe("2026-11-08");
  expect(west.displayName).toBe("B");
});
