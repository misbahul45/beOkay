import { expect, test } from "bun:test";
import {
  canonicalGlucose,
  displayGlucose,
} from "../../src/features/glucose/glucose.model.ts";
import {
  glucoseCreateSchema,
  glucosePatchSchema,
} from "../../src/features/glucose/glucose.schema.ts";

test("canonical conversion preserves precision while display rounds independently", () => {
  const canonical = canonicalGlucose(5.5, "mmol/L");
  expect(canonical.toString()).toBe("99.088");
  expect(displayGlucose(canonical, "mg/dL")).toBe(99);
  expect(displayGlucose(canonical, "mmol/L")).toBe(5.5);
  expect(canonicalGlucose(5.1234, "mmol/L").toString()).toBe("92.3031744");
  expect(canonicalGlucose(99.088, "mg/dL").div(18.016).toString()).toBe("5.5");
});
test("notes-only correction does not default or reset source measurement fields", () => {
  expect(
    glucosePatchSchema.parse({
      expectedVersion: 1,
      reason: "Correct notes",
      notes: "Updated context",
    }),
  ).toEqual({
    expectedVersion: 1,
    reason: "Correct notes",
    notes: "Updated context",
  });
});
test("manual glucose validation rejects unsupported source, unit and numeric domain", () => {
  const base = {
    id: crypto.randomUUID(),
    originalValue: 5.5,
    originalUnit: "mmol/L",
    measuredAt: new Date(Date.now() - 60000).toISOString(),
  };
  expect(glucoseCreateSchema.safeParse(base).success).toBe(true);
  for (const changed of [
    { originalValue: 0 },
    { originalValue: -1 },
    { originalValue: Infinity },
    { originalValue: 2001, originalUnit: "mg/dL" },
    { originalUnit: "invalid" },
    { source: "cgm" },
    { mealContext: "inferred_from_meal" },
    { measuredAt: "2026-02-30T12:00:00Z" },
    { originalValue: 5.12345 },
  ])
    expect(glucoseCreateSchema.safeParse({ ...base, ...changed }).success).toBe(
      false,
    );
});
