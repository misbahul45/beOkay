import { expect, test } from "bun:test";
import { dailyCoverage } from "../../src/features/insights/daily.service.ts";

test("cakupan harian: kosong = UNKNOWN, sebagian = PARTIAL, tiga domain = COMPLETE", () => {
  expect(dailyCoverage({ meals: 0, glucose: 0, activity: 0 })).toEqual({ coverageStatus: "UNKNOWN", analyticsState: "INSUFFICIENT_DATA" });
  expect(dailyCoverage({ meals: 2, glucose: 0, activity: 0 })).toEqual({ coverageStatus: "PARTIAL", analyticsState: "READY" });
  expect(dailyCoverage({ meals: 1, glucose: 3, activity: 1 })).toEqual({ coverageStatus: "COMPLETE", analyticsState: "READY" });
});
