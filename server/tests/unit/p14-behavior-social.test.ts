import { describe, expect, test } from "bun:test";
import { decide, type PolicyInput } from "../../src/features/interventions/intervention.policy.ts";
import { classifyStored, decideV3 } from "../../src/features/interventions/intervention.policy.v3.ts";
import { baselineScore, bestSlot, brier, buildFeatures, calibration, evaluate, leakageProblems, prAuc, psi, slotOfHour, splitByUserAndTime, type DayEvidence } from "../../src/features/ml/behavior/behavior.model.ts";
import { bandOf, baselineActiveDaysPerWeek, dayPoints, FORBIDDEN_RANKING_INPUTS, MIN_PEER_GROUP, peerComparison, personalBest, returnAfterBreak, weekScore } from "../../src/features/community/scoring.v2.ts";

const NOON = 12 * 60;
const base = (over: Partial<PolicyInput> = {}): PolicyInput => ({
  trigger: "COACHING_ACTION_DUE",
  nowMs: Date.parse("2026-11-10T05:00:00Z"),
  localMinute: NOON,
  consent: true,
  prefs: { pausedUntilMs: null, quietStartMinute: 1320, quietEndMinute: 420, maxPerDay: 2, maxPerWeek: 7, mutedTriggers: [] },
  hasActiveGoal: true,
  context: { deliveredToday: 0, deliveredLast7Days: 0, lastDeliveredMs: null, sameKeyDeliveredMs: null, sameKeyRespondedToday: null, sameKeyUnrespondedWithinDays: false, snoozedUntilMs: null },
  coaching: { due: true, slotStarted: true, safe: true },
  ...over,
});
const sig = { safetyHold: false, unwell: false, energy: null, dataDependent: false, dataReliable: null } as const;

describe("jitai-policy-v3", () => {
  test("tanpa sinyal baru, hasil sama dengan v2 (jam tenang, batas, jeda dipertahankan)", () => {
    const cases: Partial<PolicyInput>[] = [{}, { localMinute: 23 * 60 }, { context: { ...base().context, deliveredToday: 2 } }, { context: { ...base().context, lastDeliveredMs: Date.parse("2026-11-10T04:00:00Z") } }, { consent: false }, { trigger: "USER_REQUESTS_SUPPORT", localMinute: 23 * 60 }];
    for (const c of cases) {
      const v2 = decide(base(c)), v3 = decideV3(base(c), sig);
      expect({ option: v3.option, reason: v3.reason }).toEqual({ option: v2.option, reason: v2.reason });
    }
    expect(decideV3(base({ localMinute: 23 * 60 }), sig).decision).toBe("DEFER");
    expect(decideV3(base(), sig).decision).toBe("INTERVENE");
    expect(decideV3(base({ consent: false }), sig).decision).toBe("NO_INTERVENTION");
  });

  test("WITHHOLD: keselamatan, kurang sehat, lelah, data tidak andal, perlu tinjauan", () => {
    expect(decideV3(base(), { ...sig, safetyHold: true })).toMatchObject({ decision: "WITHHOLD", withhold: "SAFETY_HOLD", option: "NO_INTERVENTION" });
    expect(decideV3(base(), { ...sig, unwell: true }).withhold).toBe("USER_UNWELL");
    expect(decideV3(base(), { ...sig, energy: "LOW" }).withhold).toBe("LOW_ENERGY_REPORTED");
    expect(decideV3(base({ trigger: "GOAL_WINDOW_APPROACHING" }), { ...sig, dataDependent: true, dataReliable: false }).withhold).toBe("DATA_UNRELIABLE");
    expect(decideV3(base({ trigger: "GOAL_WINDOW_APPROACHING" }), { ...sig, dataDependent: true, dataReliable: true }).decision).toBe("INTERVENE");
    expect(decideV3(base({ coaching: { due: true, slotStarted: true, safe: false } }), sig)).toMatchObject({ decision: "WITHHOLD", reason: "REQUIRES_REVIEW" });
    expect(decideV3(base({ trigger: "USER_REQUESTS_SUPPORT" }), { ...sig, unwell: true }).decision).toBe("INTERVENE");
    expect(classifyStored("NO_INTERVENTION", "WITHHOLD:USER_UNWELL")).toBe("WITHHOLD");
    expect(classifyStored("NO_INTERVENTION", "QUIET_HOURS")).toBe("DEFER");
    expect(classifyStored("NO_INTERVENTION", "NO_ACTIVE_GOAL")).toBe("NO_INTERVENTION");
  });
});

describe("baseline-v1 dan harness evaluasi (fikstur sintetis, bukan kinerja)", () => {
  const days = (user: number, n: number): DayEvidence[] =>
    Array.from({ length: n }, (_, i) => ({ localDate: new Date(Date.UTC(2026, 8, 1) + i * 86_400_000).toISOString().slice(0, 10), slots: { MORNING: (i + user) % 3 === 0, EVENING: (i * user) % 5 === 1 }, observed: (i + user) % 7 !== 0 }));
  const rows = Array.from({ length: 12 }, (_, u) => buildFeatures(`u${u}`, days(u + 1, 60), [], "2026-09-29", "2026-10-30")).flat();

  test("fitur hanya dari jendela sebelum tanggal label; hari tanpa data berlabel null", () => {
    for (const r of rows) expect(r.windowEnd < r.localDate).toBe(true);
    expect(rows.some((r) => r.label === null && !r.observed)).toBe(true);
    expect(slotOfHour(6)).toBe("MORNING");
    expect(slotOfHour(23)).toBeNull();
    expect(baselineScore({ priorSlotHits28: 0, priorObservedDays28: 0 })).toBe(0.25);
    expect(bestSlot(rows.filter((r) => r.userId === "u2" && r.localDate === "2026-10-30"))).not.toBeNull();
  });

  test("pembagian per pengguna dan waktu tanpa kebocoran; metrik terhitung", () => {
    const split = splitByUserAndTime(rows, { testUserFraction: 0.4, cutoff: "2026-10-15" });
    expect(leakageProblems(split)).toEqual([]);
    expect(leakageProblems({ ...split, train: [...split.train, { ...split.test[0]!, localDate: "2026-09-01" }] }).some((p) => p.startsWith("USER_IN_BOTH"))).toBe(true);
    const r = evaluate(rows, { testUserFraction: 0.4, cutoff: "2026-10-15" });
    expect(r.leakage).toEqual([]);
    expect(r.sizes.testRows).toBeGreaterThan(0);
    expect(r.brier).toBeGreaterThanOrEqual(0);
    expect(r.claim).toContain("bukan kinerja");
    expect(brier([{ p: 1, y: 1 }, { p: 0, y: 0 }])).toBe(0);
    expect(prAuc([{ p: 0.9, y: 1 }, { p: 0.1, y: 0 }])).toBe(1);
    expect(prAuc([{ p: 0.9, y: 1 }])).toBeNull();
    expect(calibration([{ p: 0.1, y: 0 }, { p: 0.9, y: 1 }]).ece).toBeCloseTo(0.1, 5);
    expect(psi([0.1, 0.2], [0.1, 0.2])).toBeCloseTo(0, 5);
  });
});

describe("score-v2 dan bentuk sosial", () => {
  const d = (localDate: string, longest: number | null, device = 0, checkins = 0) => ({ localDate, longestSessionMinutes: longest, activeMinutesDevice: device, activeMinutesManual: longest && !device ? longest : 0, goalCheckins: checkins });
  const seq = (start: string, pattern: (number | null)[]) => pattern.map((m, i) => d(new Date(Date.parse(start + "T00:00:00Z") + i * 86_400_000).toISOString().slice(0, 10), m, m && i % 2 ? m : 0));

  test("poin harian dibatasi; perangkat 1, manual 0,8; hari istirahat 0, tidak mengurangi", () => {
    expect(dayPoints(d("2026-11-01", 30, 30))).toBe(1);
    expect(dayPoints(d("2026-11-01", 30, 0))).toBe(0.8);
    expect(dayPoints(d("2026-11-01", 5))).toBe(0);
    expect(dayPoints(d("2026-11-01", null, 0, 1))).toBe(0.8);
    const w = weekScore(seq("2026-11-01", [30, null, 30, null, 30, null, null]), 1);
    expect(w).toMatchObject({ activeDays: 3, selfProgressBonus: 0.5, version: "score-v2" });
    expect(w.total).toBeLessThanOrEqual(7 + 0.5);
  });

  test("rekor pribadi, kembali setelah jeda, pita sebaya minimum 5", () => {
    const f = seq("2026-10-01", [20, 20, 20, null, 20, 20, 20, 20, null, null, null, null, null, null, null, null, null, 25]);
    expect(personalBest(f)).toMatchObject({ longestStreak: 4, best7DayActive: 6 });
    expect(returnAfterBreak(f, f.at(-1)!.localDate)).toEqual({ returned: true, gapDays: 9 });
    expect(returnAfterBreak(f, f.at(-2)!.localDate).returned).toBe(false);
    expect(baselineActiveDaysPerWeek(f.slice(0, 13))).toBeNull();
    expect(bandOf(2)).toBe("2-3");
    expect(bandOf(null)).toBeNull();
    expect(peerComparison(3, [1, 2, 3])).toEqual({ comparable: false, groupSize: 4, half: null });
    expect(peerComparison(3, [1, 2, 4, 5])).toMatchObject({ comparable: true, groupSize: MIN_PEER_GROUP, half: "UPPER" });
  });

  test("variabel peringkat terlarang tidak dipakai di modul skor", async () => {
    const src = await Bun.file(new URL("../../src/features/community/scoring.v2.ts", import.meta.url)).text();
    const body = src.split("export const FORBIDDEN_RANKING_INPUTS")[1]!.split("\n").slice(1).join("\n");
    for (const w of FORBIDDEN_RANKING_INPUTS) expect(body).not.toMatch(new RegExp(`\\.${w}\\b|\\b${w}\\s*:`, "i"));
  });
});

import { dayPartOfHour, derivedActivityTime } from "../../src/features/memory/memory.service.ts";
import { validateProposal } from "../../src/features/agent/skills/llm-planner.ts";

describe("memori turunan dan perencana bayangan", () => {
  test("rutinitas hanya diusulkan bila ≥4 sesi dan ≥60% di satu bagian hari", () => {
    expect(dayPartOfHour(6)).toBe("pagi");
    expect(dayPartOfHour(12)).toBe("siang");
    expect(dayPartOfHour(16)).toBe("sore");
    expect(dayPartOfHour(20)).toBe("malam");
    expect(dayPartOfHour(2)).toBeNull();
    expect(derivedActivityTime([6, 7, 6])).toBeNull();
    expect(derivedActivityTime([6, 7, 6, 19])).toEqual({ part: "pagi", count: 3, total: 4 });
    expect(derivedActivityTime([6, 7, 19, 20])).toBeNull();
    expect(derivedActivityTime([2, 3, 6, 7])).toBeNull();
  });
  test("usulan perencana divalidasi terhadap daftar alat skill", () => {
    expect(validateProposal({ tool: "search_knowledge", reason: "x" }, ["search_knowledge"])).toEqual({ tool: "search_knowledge", reason: "x" });
    expect(validateProposal({ tool: null }, ["search_knowledge"])).toEqual({ tool: null, reason: null });
    expect(validateProposal({ tool: "change_medication" }, ["search_knowledge"])).toEqual({ error: "TOOL_NOT_ALLOWED" });
    expect(validateProposal({ step: 1 }, ["search_knowledge"])).toEqual({ error: "BAD_SHAPE" });
  });
});
