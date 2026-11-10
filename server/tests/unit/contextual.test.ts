import { expect, test } from "bun:test";
import { buildContextualInsights, loggingStreak, type ContextSnapshot } from "../../src/features/insights/contextual.model.ts";

const base: ContextSnapshot = {
  localDate: "2026-11-12", localHour: 10, isoWeekday: 4,
  medication: { scheduledPastDueUnknown: 0, scheduledTotal: 0 },
  mealsToday: 1,
  glucose: { totalRecords: 0, daysSinceLast: null },
  activity: { lastWeekActiveDays: null, weekBeforeActiveDays: null },
  goals: [], loggingStreakDays: 0,
};
const codes = (s: Partial<ContextSnapshot>) => buildContextualInsights({ ...base, ...s }).items.map((i) => i.code);

test("tanpa data tidak ada insight (tidak mengarang)", () => {
  expect(buildContextualInsights(base)).toMatchObject({ items: [], suppressed: 0 });
});

test("obat lewat jadwal dan belum dikonfirmasi; tidak mengasumsikan sudah diminum", () => {
  const r = buildContextualInsights({ ...base, medication: { scheduledPastDueUnknown: 2, scheduledTotal: 3 } });
  expect(r.items[0]).toMatchObject({ code: "MEDICATION_UNCONFIRMED", evidence: { unconfirmed: 2, scheduledToday: 3 } });
  expect(r.items[0]!.body).toContain("hanya bila memang sudah kamu lakukan");
});

test("catatan makan kosong baru disebut setelah pukul 14", () => {
  expect(codes({ mealsToday: 0, localHour: 13 })).not.toContain("NO_MEAL_LOGGED_TODAY");
  expect(codes({ mealsToday: 0, localHour: 14 })).toContain("NO_MEAL_LOGGED_TODAY");
});

test("tujuan mingguan di bawah separuh hanya disebut mulai Kamis, dan hanya yang paling tertinggal", () => {
  const goals = [
    { id: "a", title: "Jalan", period: "weekly", value: 1, target: 5 },
    { id: "b", title: "Catat makan", period: "weekly", value: 0, target: 4 },
    { id: "c", title: "Harian", period: "daily", value: 0, target: 1 },
    { id: "d", title: "Aman", period: "weekly", value: 4, target: 5 },
  ];
  expect(codes({ goals, isoWeekday: 3 })).not.toContain("GOAL_BELOW_HALF");
  const r = buildContextualInsights({ ...base, goals, isoWeekday: 4 });
  const g = r.items.filter((i) => i.code === "GOAL_BELOW_HALF");
  expect(g).toHaveLength(1);
  expect(g[0]!.evidence).toMatchObject({ goalId: "b", value: 0, target: 4 });
});

test("jarak catatan glukosa tidak menilai angka dan hanya untuk yang rutin mencatat", () => {
  expect(codes({ glucose: { totalRecords: 2, daysSinceLast: 10 } })).not.toContain("GLUCOSE_LOG_GAP");
  expect(codes({ glucose: { totalRecords: 5, daysSinceLast: 2 } })).not.toContain("GLUCOSE_LOG_GAP");
  const r = buildContextualInsights({ ...base, glucose: { totalRecords: 5, daysSinceLast: 4 } });
  expect(r.items[0]!.code).toBe("GLUCOSE_LOG_GAP");
  expect(JSON.stringify(r).toLowerCase()).not.toMatch(/tinggi|rendah|normal|bahaya|hipo|hiper|mg\/dl/);
});

test("maksimal tiga insight, urut prioritas, sisanya dihitung sebagai suppressed", () => {
  const r = buildContextualInsights({
    ...base, localHour: 16, mealsToday: 0, isoWeekday: 5,
    medication: { scheduledPastDueUnknown: 1, scheduledTotal: 1 },
    goals: [{ id: "a", title: "Jalan", period: "weekly", value: 0, target: 3 }],
    glucose: { totalRecords: 9, daysSinceLast: 5 },
    loggingStreakDays: 4,
    activity: { lastWeekActiveDays: 3, weekBeforeActiveDays: 2 },
  });
  expect(r.items.map((i) => i.code)).toEqual(["MEDICATION_UNCONFIRMED", "NO_MEAL_LOGGED_TODAY", "GOAL_BELOW_HALF"]);
  expect(r.suppressed).toBe(3);
});

test("rangkaian mencatat dihitung berturut-turut sampai hari ini atau kemarin, putus bila ada hari kosong", () => {
  expect(loggingStreak(["2026-11-12", "2026-11-11", "2026-11-10", "2026-11-08"], "2026-11-12")).toBe(3);
  expect(loggingStreak(["2026-11-11", "2026-11-10"], "2026-11-12")).toBe(2); // belum mencatat hari ini, rangkaian belum putus
  expect(loggingStreak(["2026-11-09"], "2026-11-12")).toBe(0);
  expect(loggingStreak([], "2026-11-12")).toBe(0);
});
