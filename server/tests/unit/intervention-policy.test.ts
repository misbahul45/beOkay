import { expect, test } from "bun:test";
import { MIN_GAP_MS, contentFor, decide, inQuietHours, type PolicyInput } from "../../src/features/interventions/intervention.policy.ts";

const base = (over: Partial<PolicyInput> = {}, ctx: Partial<PolicyInput["context"]> = {}, prefs: Partial<PolicyInput["prefs"]> = {}): PolicyInput => ({
  trigger: "GOAL_WINDOW_APPROACHING",
  nowMs: 1_800_000_000_000,
  localMinute: 10 * 60,
  consent: true,
  prefs: { pausedUntilMs: null, quietStartMinute: 22 * 60, quietEndMinute: 7 * 60, maxPerDay: 2, maxPerWeek: 7, mutedTriggers: [], ...prefs },
  hasActiveGoal: true,
  context: { deliveredToday: 0, deliveredLast7Days: 0, lastDeliveredMs: null, sameKeyDeliveredMs: null, sameKeyRespondedToday: null, sameKeyUnrespondedWithinDays: false, snoozedUntilMs: null, ...ctx },
  ...over,
});

test("jam tenang: melewati tengah malam, batas awal inklusif dan akhir eksklusif, awal = akhir berarti tanpa jam tenang", () => {
  expect(inQuietHours(23 * 60, 22 * 60, 7 * 60)).toBe(true);
  expect(inQuietHours(3 * 60, 22 * 60, 7 * 60)).toBe(true);
  expect(inQuietHours(22 * 60, 22 * 60, 7 * 60)).toBe(true);
  expect(inQuietHours(7 * 60, 22 * 60, 7 * 60)).toBe(false);
  expect(inQuietHours(12 * 60, 22 * 60, 7 * 60)).toBe(false);
  expect(inQuietHours(13 * 60, 9 * 60, 17 * 60)).toBe(true); // jam tenang siang hari
  expect(inQuietHours(5, 600, 600)).toBe(false);
});

test("tanpa persetujuan: tidak ada intervensi, apa pun yang lain", () => {
  expect(decide(base({ consent: false }))).toMatchObject({ option: "NO_INTERVENTION", reason: "CONSENT_MISSING" });
});

test("urutan alasan: jeda → jenis dimatikan → tujuan → sudah dikerjakan → ditunda → duplikat → jam tenang → jatah → terlalu cepat", () => {
  const now = base().nowMs;
  const why = (r: ReturnType<typeof decide>) => r.reason;
  expect(why(decide(base({}, {}, { pausedUntilMs: now + 1 })))).toBe("COACHING_PAUSED");
  expect(why(decide(base({}, {}, { mutedTriggers: ["GOAL_WINDOW_APPROACHING"] })))).toBe("TRIGGER_MUTED");
  expect(why(decide(base({ hasActiveGoal: false })))).toBe("NO_ACTIVE_GOAL");
  expect(why(decide(base({}, { sameKeyRespondedToday: "ALREADY_DONE" })))).toBe("ALREADY_DONE_TODAY");
  expect(why(decide(base({}, { snoozedUntilMs: now + 5 })))).toBe("SNOOZED");
  expect(why(decide(base({}, { sameKeyDeliveredMs: now - 1000 })))).toBe("DUPLICATE");
  expect(why(decide(base({}, { sameKeyUnrespondedWithinDays: true })))).toBe("REPEAT_SUPPRESSED");
  expect(why(decide(base({ localMinute: 23 * 60 })))).toBe("QUIET_HOURS");
  expect(why(decide(base({}, { deliveredToday: 2 })))).toBe("DAILY_LIMIT");
  expect(why(decide(base({}, { deliveredLast7Days: 7 })))).toBe("WEEKLY_LIMIT");
  expect(why(decide(base({}, { lastDeliveredMs: now - MIN_GAP_MS + 1 })))).toBe("TOO_SOON");
  expect(decide(base())).toEqual({ option: "GOAL_REVIEW_CARD", reason: null, coverage: "FULL" });
});

test("permintaan sendiri: boleh di jam tenang, saat dijeda, dan tidak memakai jatah proaktif; tetap tunduk pada persetujuan, jenis yang dimatikan, dan duplikat", () => {
  const u = (ctx: Partial<PolicyInput["context"]> = {}, prefs: Partial<PolicyInput["prefs"]> = {}, over: Partial<PolicyInput> = {}) => decide(base({ trigger: "USER_REQUESTS_SUPPORT", hasActiveGoal: false, localMinute: 2 * 60, ...over }, { deliveredToday: 9, deliveredLast7Days: 99, ...ctx }, { pausedUntilMs: base().nowMs + 1e6, ...prefs }));
  expect(u()).toMatchObject({ option: "IN_APP_SUGGESTION", reason: null });
  expect(u({}, {}, { consent: false }).reason).toBe("CONSENT_MISSING");
  expect(u({}, { mutedTriggers: ["USER_REQUESTS_SUPPORT"] }).reason).toBe("TRIGGER_MUTED");
  expect(u({ sameKeyDeliveredMs: base().nowMs - 10 }).reason).toBe("DUPLICATE");
});

test("pemicu mingguan memberi refleksi mingguan; tanpa tujuan tidak perlu; isi pesan dari daftar tetap tanpa klaim kesehatan", () => {
  expect(decide(base({ trigger: "WEEKLY_REVIEW_AVAILABLE", hasActiveGoal: false }))).toMatchObject({ option: "WEEKLY_REFLECTION", coverage: "PARTIAL" });
  for (const t of ["USER_REQUESTS_SUPPORT", "GOAL_WINDOW_APPROACHING", "USER_SELECTED_ROUTINE_REMINDER", "WEEKLY_REVIEW_AVAILABLE"] as const) {
    const c = contentFor(t, "Jalan sore");
    expect(Object.keys(c).sort()).toEqual(["action", "body", "title"]);
    expect(`${c.title} ${c.body}`).not.toMatch(/glukosa|gula darah|obat|dosis|diabetes|menurunkan|risiko|segera|harus|wajib/i);
  }
});
