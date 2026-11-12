import { expect, test } from "bun:test";
import { change, hba1cStatus, labProblem, vitalProblem } from "../../src/features/clinical/clinical.model.ts";
import { goalAdjustments, percentile, raisedTarget, type GoalWeek } from "../../src/features/coaching/coaching.model.ts";
import { STRATEGIES, findStrategy } from "../../src/features/coaching/coaching.strategies.ts";
import { glucoseAlert } from "../../src/features/glucose/glucose.alerts.ts";
import { categoryForHour, mealSignature, mealTitle, rankActivities, rankMeals } from "../../src/features/quick-record/quick-record.model.ts";
import { compare, glucoseLine, insufficientLine, pairAround } from "../../src/features/record-context/record-context.model.ts";
import { cutoffs } from "../../src/features/retention/retention.service.ts";
import { mapAudit } from "../../src/features/usage/usage.audit.ts";
import { acceptableTime, clientBatchSchema, median } from "../../src/features/usage/usage.model.ts";

test("Analitik: hanya jenis peristiwa tanpa teks bebas; peristiwa audit dipetakan tanpa isi kesehatan", () => {
  const now = new Date();
  const ok = clientBatchSchema.safeParse({ platform: "android", appVersion: "1.0.0+1", events: [{ type: "form_saved", domain: "glucose", meta: { via: "form", durationMs: 4200 }, occurredAt: now.toISOString() }] });
  expect(ok.success).toBe(true);
  expect(clientBatchSchema.safeParse({ events: [{ type: "form_saved", meta: { note: "gula 250" }, occurredAt: now.toISOString() }] }).success).toBe(false);
  expect(clientBatchSchema.safeParse({ events: [{ type: "record_created", occurredAt: now.toISOString() }] }).success).toBe(false);
  expect(clientBatchSchema.safeParse({ events: [{ type: "screen_opened", meta: { screen: "Glukosa 250!" }, occurredAt: now.toISOString() }] }).success).toBe(false);
  expect(acceptableTime(new Date(now.getTime() - 8 * 86_400_000), now)).toBe(false);
  expect(acceptableTime(new Date(now.getTime() + 60 * 60_000), now)).toBe(false);
  expect(acceptableTime(new Date(now.getTime() - 60_000), now)).toBe(true);
  expect(mapAudit({ userId: "u", eventType: "glucose_recorded", metadata: { recordId: "x" } })).toEqual({ type: "record_created", domain: "glucose" });
  expect(mapAudit({ userId: "u", eventType: "coaching_decided", metadata: { decision: "ACCEPT", source: "MEAL_LOG_GAP" } })).toEqual({ type: "suggestion_accepted", domain: "coaching", meta: { source: "meal_log_gap" } });
  expect(mapAudit({ userId: "u", eventType: "coaching_decided", metadata: { decision: "WITHDRAW" } })).toBeNull();
  expect(mapAudit({ userId: "u", eventType: "consent_granted" })).toBeNull();
  expect(median([3, 1, 2])).toBe(2);
  expect(median([4, 1, 2, 3])).toBe(2.5);
  expect(median([])).toBeNull();
});

test("Jangkar klinis: batas nilai dan satuan sama dengan CHECK, perubahan deskriptif, HbA1c 90 hari", () => {
  expect(vitalProblem("weight", "kg", 72.5, null)).toBeNull();
  expect(vitalProblem("weight", "lb", 160, null)).toBe("UNIT_NOT_ALLOWED");
  expect(vitalProblem("weight", "kg", 9, null)).toBe("VALUE_OUT_OF_RANGE");
  expect(vitalProblem("blood_pressure", "mmHg", 120, 80)).toBeNull();
  expect(vitalProblem("blood_pressure", "mmHg", 80, 120)).toBe("SYSTOLIC_NOT_ABOVE_DIASTOLIC");
  expect(vitalProblem("blood_pressure", "mmHg", 120, null)).toBe("VALUE_OUT_OF_RANGE");
  expect(vitalProblem("height", "cm", 165, 3)).toBe("SECOND_VALUE_NOT_ALLOWED");
  expect(labProblem("hba1c", "%", 7.2)).toBeNull();
  expect(labProblem("hba1c", "%", 30)).toBe("VALUE_OUT_OF_RANGE");
  expect(labProblem("hba1c", "mmol/mol", 55)).toBeNull();
  expect(labProblem("ldl", "%", 100)).toBe("UNIT_NOT_ALLOWED");
  expect(change(72, 74.5)).toEqual({ difference: -2.5, direction: "DOWN" });
  expect(change(72, null)).toBeNull();
  expect(hba1cStatus(null, "2026-11-12")).toMatchObject({ status: "NONE" });
  expect(hba1cStatus("2026-08-14", "2026-11-12")).toMatchObject({ status: "DUE", daysSince: 90, dueOn: "2026-11-12" });
  expect(hba1cStatus("2026-08-15", "2026-11-12")).toMatchObject({ status: "RECENT", daysSince: 89 });
});

test("Pesan ambang glukosa memakai batas yang sama dengan keselamatan Asisten", () => {
  expect(glucoseAlert(69.9)?.level).toBe("LOW");
  expect(glucoseAlert(70)).toBeNull();
  expect(glucoseAlert(299.9)).toBeNull();
  expect(glucoseAlert(300)).toMatchObject({ level: "HIGH", policyVersion: "safety-policy-v2", thresholdMgDl: 300 });
  expect(glucoseAlert(52)!.message).toContain("119");
});

test("Catat cepat: kelompok berdasarkan isi yang sama, frekuensi lalu terbaru, kategori menurut jam", () => {
  const item = (name: string, foodId: string | null = null) => ({ foodId, name, quantity: 1, unit: "portion", grams: 150, gramsBasis: "user_estimate" });
  const at = (h: number) => new Date(Date.UTC(2026, 10, 10, h));
  const a = { id: "1", category: "breakfast", consumedAt: at(1), items: [item("Nasi uduk", "f1"), item("Teh manis")] };
  const b = { id: "2", category: "breakfast", consumedAt: at(2), items: [item("Teh manis"), item("Nasi uduk", "f1")] };
  const c = { id: "3", category: "lunch", consumedAt: at(5), items: [item("Gado-gado")] };
  expect(mealSignature(a)).toBe(mealSignature(b));
  const ranked = rankMeals([a, b, c]);
  expect(ranked.map((r) => [r.count, r.latest.id])).toEqual([[2, "2"], [1, "3"]]);
  expect(mealTitle([item("A"), item("B"), item("C"), item("D"), item("E")])).toBe("A, B, C +2");
  const act = (id: string, m: number, h: number) => ({ id, activityType: "walking", durationMinutes: m, reportedIntensity: "light", startedAt: at(h) });
  expect(rankActivities([act("x", 20, 1), act("y", 30, 2), act("z", 20, 3)]).map((r) => [r.count, r.latest.id])).toEqual([[2, "z"], [1, "y"]]);
  expect([categoryForHour(6), categoryForHour(12), categoryForHour(19), categoryForHour(23), categoryForHour(15)]).toEqual(["breakfast", "lunch", "dinner", "snack", "snack"]);
});

test("Konteks saat simpan: median pribadi minimal 3 catatan, kalimat netral, pasangan glukosa sekitar makan", () => {
  expect(compare(120, [130, 128])).toBeNull();
  expect(compare(110, [130, 128, 126])).toEqual({ median: 128, n: 3, comparison: "LOWER" });
  expect(compare(130, [130, 128, 126])!.comparison).toBe("SIMILAR");
  expect(compare(160, [130, 128, 126])!.comparison).toBe("HIGHER");
  expect(glucoseLine({ median: 128, n: 9, comparison: "LOWER" }, "fasting", "mg/dL")).toBe("Lebih rendah dari median puasa 14 harimu: 128 mg/dL dari 9 catatan.");
  expect(glucoseLine({ median: 6.5, n: 4, comparison: "SIMILAR" }, null, "mmol/L")).toBe("Mirip dengan median 14 harimu: 6,5 mmol/L dari 4 catatan.");
  expect(insufficientLine(1)).toContain("1 dari 3");
  const t = new Date("2026-11-10T05:00:00Z");
  const r = (id: string, min: number, value: number) => ({ id, at: new Date(t.getTime() + min * 60_000), value, mealContext: "unknown" });
  const pair = pairAround(t, [r("early", -120, 90), r("before", -20, 110), r("a1", 70, 170), r("a2", 115, 160), r("late", 200, 120)]);
  expect([pair.before?.id, pair.after?.id]).toEqual(["before", "a2"]);
  expect(pairAround(t, [r("late", 200, 120)])).toEqual({ before: null, after: null });
});

test("Tujuan adaptif dua arah: naik hanya bila tercapai berulang, paling banyak 10% atau +1, turun seperti v1", () => {
  const g = (over: Partial<GoalWeek>): GoalWeek => ({ id: "g", title: "Aktif", goalType: "activity_minutes", period: "weekly", target: 150, value: 160, version: 2, history: [170, 150, 140], ...over });
  expect(percentile([160, 170, 150, 140], 0.6)).toBeCloseTo(158, 6);
  const up = goalAdjustments([g({})]);
  expect(up).toHaveLength(1);
  expect(up[0]).toMatchObject({ direction: "UP", fromTarget: 150, toTarget: 155, expectedVersion: 2 });
  expect(up[0]!.basis).toContain("Tercapai di 3 dari 4 minggu");
  expect(goalAdjustments([g({ history: [200, 210, 220], value: 230 })])[0]!.toTarget).toBe(165);
  expect(goalAdjustments([g({ history: [100, 90, null] })])).toEqual([]);
  expect(goalAdjustments([g({ history: [null, null, null] })])).toEqual([]);
  expect(goalAdjustments([g({ value: 120 })])).toEqual([]);
  expect(goalAdjustments([g({ value: 45, history: [] })])[0]).toMatchObject({ direction: "DOWN", toTarget: 80 });
  expect(goalAdjustments([g({ goalType: "walking_sessions", target: 3, value: 5, history: [5, 4, 3] })])[0]).toMatchObject({ direction: "UP", toTarget: 4 });
  expect(goalAdjustments([g({ goalType: "record_meals", target: 7, value: 7, history: [7, 7, 7] })])).toEqual([]);
  expect(raisedTarget("activity_minutes", 50, 80)).toBe(55);
  expect(raisedTarget("activity_minutes", 150, 150)).toBeNull();
});

test("Daftar strategi problem solving: setiap hambatan punya 2–3 strategi dengan kunci unik", () => {
  const keys = Object.values(STRATEGIES).flat().map((s) => s.key);
  expect(new Set(keys).size).toBe(keys.length);
  for (const list of Object.values(STRATEGIES)) expect(list.length >= 2 && list.length <= 3).toBe(true);
  expect(findStrategy("TIME", "TIME_SPLIT")?.title).toBe("Bagi jadi potongan 10 menit");
  expect(findStrategy("TIME", "FORGOT_PAIR")).toBeNull();
});

test("Retensi: batas waktu dihitung dari konfigurasi", () => {
  const now = new Date("2026-11-12T00:00:00Z");
  const c = cutoffs({ agentEventsDays: 90, readNotificationsDays: 60, auditDays: 365, usageDays: 400, outboxDays: 30 }, now);
  expect(c.agentEvents.toISOString().slice(0, 10)).toBe("2026-08-14");
  expect(c.readNotifications.toISOString().slice(0, 10)).toBe("2026-09-13");
  expect(c.audit.toISOString().slice(0, 10)).toBe("2025-11-12");
});
