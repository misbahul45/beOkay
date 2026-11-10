import { expect, test } from "bun:test";
import { MIN_COHORT, aliasKey, aliasProblem, desiredEvents, rank, reconcile, totalScore } from "../../src/features/community/scoring.model.ts";

const input = (over: object = {}) => ({ targetDays: 20, periodDays: 28, activityDays: [] as string[], checkinDays: [] as string[], ...over });

test("tanpa catatan skor 0 dan tidak ada partisipasi; satu hari menambah partisipasi sekali", () => {
  expect(desiredEvents(input())).toEqual([]);
  const d = desiredEvents(input({ activityDays: ["2026-11-10"] }));
  expect(d.map((e) => e.eventType).sort()).toEqual(["ACTIVITY_DAY", "PARTICIPATION"]);
  expect(totalScore(d)).toBe(22.5); // 50/20 + 20
});

test("hari di atas target tidak menambah skor (tidak ada hadiah untuk berlebihan) dan hari duplikat dihitung sekali", () => {
  const days = Array.from({ length: 28 }, (_, i) => `2026-11-${String(i + 1).padStart(2, "0")}`);
  const d = desiredEvents(input({ activityDays: [...days, ...days] }));
  expect(d.filter((e) => e.eventType === "ACTIVITY_DAY")).toHaveLength(20);
  expect(totalScore(d)).toBe(70); // 50 + 20 partisipasi
});

test("skor maksimum 100 hanya dengan target hari aktif + check-in penuh + partisipasi", () => {
  const days = Array.from({ length: 28 }, (_, i) => `2026-11-${String(i + 1).padStart(2, "0")}`);
  expect(totalScore(desiredEvents(input({ activityDays: days, checkinDays: days })))).toBe(100);
});

test("rekonsiliasi idempoten: keadaan sama tidak menghasilkan perubahan", () => {
  const desired = desiredEvents(input({ activityDays: ["2026-11-10", "2026-11-11"] }));
  const first = reconcile([], desired);
  expect(first.toAdd).toHaveLength(3);
  const ledger = first.toAdd.map((a, i) => ({ id: `e${i}`, eventType: a.eventType, sourceKey: a.sourceKey, points: a.points, reversalOf: null }));
  expect(reconcile(ledger, desired)).toEqual({ toAdd: [], toReverse: [] });
});

test("sumber dikoreksi/diarsipkan: poin dibalik; bila memenuhi syarat lagi, ditambah dengan kunci baru (#2)", () => {
  const both = desiredEvents(input({ activityDays: ["2026-11-10", "2026-11-11"] }));
  const ledger = reconcile([], both).toAdd.map((a, i) => ({ id: `e${i}`, eventType: a.eventType, sourceKey: a.sourceKey, points: a.points, reversalOf: null as string | null }));
  const one = desiredEvents(input({ activityDays: ["2026-11-10"] }));
  const r = reconcile(ledger, one);
  expect(r.toAdd).toEqual([]);
  expect(r.toReverse.map((e) => e.sourceKey)).toEqual(["day:2026-11-11"]);
  const withReversal = [...ledger, { id: "rev", eventType: "ACTIVITY_DAY", sourceKey: "day:2026-11-11", points: -2.5, reversalOf: ledger.find((l) => l.sourceKey === "day:2026-11-11")!.id }];
  expect(totalScore(withReversal)).toBe(22.5);
  // semua sumber hilang: partisipasi juga dibalik
  expect(reconcile(withReversal, desiredEvents(input())).toReverse.map((e) => e.eventType).sort()).toEqual(["ACTIVITY_DAY", "PARTICIPATION"]);
  // memenuhi syarat lagi → baris asli baru dengan akhiran, bukan menimpa baris lama
  const back = reconcile(withReversal, both);
  expect(back.toAdd.map((a) => a.sourceKey)).toEqual(["day:2026-11-11#2"]);
});

test("peringkat kompetisi: seri berbagi peringkat, urutan stabil menurut alias", () => {
  const r = rank([{ alias: "Cici", score: 40 }, { alias: "Abi", score: 70 }, { alias: "Beni", score: 40 }, { alias: "Dedi", score: 10 }]);
  expect(r.map((x) => [x.alias, x.rank])).toEqual([["Abi", 1], ["Beni", 2], ["Cici", 2], ["Dedi", 4]]);
});

test("alias: menolak surel, telepon, kata yang menyamar staf, dan format salah", () => {
  expect(aliasProblem("Sehat Selalu")).toBeNull();
  for (const bad of ["ab", "a@b.com", "0812345678901", "Admin Resmi", "beOkay Team", "-awal", "terlalu panjang sekali melebihi batas"]) expect(aliasProblem(bad)).not.toBeNull();
  expect(aliasKey("  Sehat   Selalu ")).toBe("sehat selalu");
  expect(MIN_COHORT).toBe(5);
});
