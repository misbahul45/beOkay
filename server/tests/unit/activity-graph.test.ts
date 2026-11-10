import { expect, test } from "bun:test";
import { buildActivityCandidates, type SessionLite } from "../../src/features/agent/activity.graph.ts";

const s = (type: string, minutes: number, i = 0): SessionLite => ({ type, minutes, at: new Date(Date.now() - i * 86_400_000).toISOString(), source: "manual" });

test("tanpa riwayat: satu contoh awal singkat, data NONE, bukan resep", () => {
  const r = buildActivityCandidates([]);
  expect(r.coverage).toBe("NONE");
  expect(r.candidates).toHaveLength(1);
  expect(r.candidates[0]).toMatchObject({ type: "walking", minutes: 10 });
  expect(r.candidates[0]!.basis).toContain("Belum ada riwayat");
});

test("durasi tidak pernah melebihi sesi terpanjang jenis itu (tidak ada eskalasi), versi singkat lebih pendek", () => {
  const r = buildActivityCandidates([s("walking", 20, 1), s("walking", 30, 2), s("walking", 40, 3), s("walking", 25, 4), s("cycling", 30, 5)]);
  expect(r.coverage).toBe("OK");
  for (const c of r.candidates) {
    const cap = c.type === "walking" ? 40 : 30;
    expect(c.minutes).toBeLessThanOrEqual(cap);
    expect(c.minutes).toBeGreaterThanOrEqual(5);
  }
  expect(r.candidates[0]).toMatchObject({ type: "walking" });
  const short = r.candidates.find((c) => c.key.startsWith("short:"))!;
  expect(short.minutes).toBeLessThan(r.candidates[0]!.minutes);
  expect(r.candidates.some((c) => c.type === "cycling")).toBe(true);
  expect(r.candidates.length).toBeLessThanOrEqual(3);
});

test("riwayat sedikit ditandai SPARSE; jenis yang belum pernah dilakukan tidak ditawarkan", () => {
  const r = buildActivityCandidates([s("strength", 15, 1), s("strength", 15, 2)]);
  expect(r.coverage).toBe("SPARSE");
  expect(r.candidates.every((c) => c.type === "strength")).toBe(true);
  expect(r.candidates.every((c) => c.minutes <= 15)).toBe(true);
});

test("deterministik: masukan sama menghasilkan keluaran sama", () => {
  const h = [s("walking", 30, 1), s("running", 20, 2), s("walking", 30, 3)];
  expect(buildActivityCandidates(h)).toEqual(buildActivityCandidates(h));
});
