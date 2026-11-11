import { expect, test } from "bun:test";
import { applyActivityConstraints, type ActivityCandidate } from "../../src/features/agent/activity.graph.ts";
import { routeMessage } from "../../src/features/conversation/conversation.router.ts";
import { inferMealTime, zonedInstant } from "../../src/features/meal-drafts/meal-draft.service.ts";
import { isMealLogStatement, parseMealText } from "../../src/features/meal-drafts/meal-text.parser.ts";
import { activityConstraintsFrom, extractMemoryCandidates } from "../../src/features/memory/memory.extract.ts";

test("Parser: kategori, pemisahan makanan, jumlah dan satuan; gram hanya bila disebut", () => {
  const a = parseMealText("Tadi siang makan nasi satu piring, ayam bakar, dan lalapan");
  expect(a.category).toBe("lunch");
  expect(a.items.map((i) => i.name)).toEqual(["nasi", "ayam bakar", "lalapan"]);
  expect(a.items[0]).toMatchObject({ quantity: 1, unit: "portion", unitLabel: "piring", quantityStated: true, grams: null });
  expect(a.items[1]).toMatchObject({ quantity: 1, unit: "portion", unitLabel: null, quantityStated: false, grams: null });

  const b = parseMealText("sarapan roti 2 lembar sama telur rebus");
  expect(b.category).toBe("breakfast");
  expect(b.items[0]).toMatchObject({ name: "roti", quantity: 2, unit: "piece", unitLabel: "lembar" });
  expect(b.items[1]!.name).toBe("telur rebus");

  const c = parseMealText("aku makan nasi goreng 300 gram");
  expect(c.items).toEqual([expect.objectContaining({ name: "nasi goreng", quantity: 300, unit: "g", grams: 300 })]);

  const d = parseMealText("tadi minum segelas teh manis");
  expect(d.items[0]).toMatchObject({ name: "teh manis", quantity: 1, unit: "portion", unitLabel: "gelas" });

  const e = parseMealText("barusan ngemil setengah bungkus keripik");
  expect(e.category).toBe("snack");
  expect(e.items[0]).toMatchObject({ name: "keripik", quantity: 0.5, unitLabel: "bungkus" });
});

test("Parser: pernyataan makan dibedakan dari pertanyaan", () => {
  expect(isMealLogStatement("Tadi siang makan nasi satu piring, ayam bakar, dan lalapan")).toBe(true);
  expect(isMealLogStatement("aku makan nasi goreng 300 gram")).toBe(true);
  expect(isMealLogStatement("barusan sarapan bubur ayam")).toBe(true);
  expect(isMealLogStatement("berapa kalori nasi goreng?")).toBe(false);
  expect(isMealLogStatement("makan apa ya hari ini")).toBe(false);
  expect(isMealLogStatement("aku makan apa ya")).toBe(false);
  expect(isMealLogStatement("cari info nasi goreng")).toBe(false);
});

test("Waktu makan: jam lokal zona pengguna, tidak pernah di masa depan", () => {
  expect(zonedInstant("2026-11-10", "07:00", "Asia/Jakarta").toISOString()).toBe("2026-11-10T00:00:00.000Z");
  const evening = new Date("2026-11-10T13:00:00Z");
  expect(inferMealTime("lunch", evening, "Asia/Jakarta").consumedAt.toISOString()).toBe("2026-11-10T05:30:00.000Z");
  const afternoon = new Date("2026-11-10T08:00:00Z");
  expect(inferMealTime("dinner", afternoon, "Asia/Jakarta").consumedAt).toEqual(afternoon);
  const morning = new Date("2026-11-10T01:00:00Z");
  expect(inferMealTime(null, morning, "Asia/Jakarta")).toEqual({ category: "breakfast", consumedAt: morning });
});

test("Ekstraksi memori: hanya preferensi yang dinyatakan; topik sensitif tidak pernah diusulkan", () => {
  expect(extractMemoryCandidates("aku lebih suka olahraga pagi")).toEqual([{ kind: "ACTIVITY_TIME", key: "ACTIVITY_TIME", content: "Lebih suka beraktivitas pagi hari" }]);
  expect(extractMemoryCandidates("aku sibuk tiap sore")).toEqual([{ kind: "SCHEDULE", key: "SCHEDULE:sore", content: "Sering sibuk di sore hari" }]);
  expect(extractMemoryCandidates("aku cuma bisa 15 menit")[0]).toMatchObject({ kind: "AVAILABLE_MINUTES", content: "Punya waktu sekitar 15 menit untuk aktivitas" });
  const mixed = extractMemoryCandidates("aku nggak suka lari tapi suka bersepeda");
  expect(mixed.map((m) => m.key).sort()).toEqual(["ACTIVITY_DISLIKE:running:lari", "ACTIVITY_LIKE:cycling:bersepeda"]);
  expect(extractMemoryCandidates("aku lebih suka minum obat pagi")).toEqual([]);
  expect(extractMemoryCandidates("gula darahku biasanya sore naik")).toEqual([]);
  expect(extractMemoryCandidates("akhir-akhir ini sibuk")).toEqual([]);
  expect(extractMemoryCandidates("ide olahraga 15 menit")).toEqual([]);
});

test("Batasan aktivitas dari memori dan permintaan hanya memendekkan, tidak pernah menambah", () => {
  const c = activityConstraintsFrom([
    { kind: "AVAILABLE_MINUTES", key: "AVAILABLE_MINUTES", content: "Punya waktu sekitar 15 menit untuk aktivitas" },
    { kind: "ACTIVITY_DISLIKE", key: "ACTIVITY_DISLIKE:running:lari", content: "Kurang suka lari" },
  ]);
  expect(c).toEqual({ avoidTypes: ["running"], maxMinutes: 15 });
  const base: ActivityCandidate[] = [
    { key: "same:walking:30", type: "walking", minutes: 30, title: "Jalan kaki 30 menit", basis: "x", rank: 1 },
    { key: "short:walking:20", type: "walking", minutes: 20, title: "Jalan kaki 20 menit", basis: "x", rank: 2 },
    { key: "alt:running:20", type: "running", minutes: 20, title: "Lari 20 menit", basis: "x", rank: 3 },
  ];
  const out = applyActivityConstraints(base, c);
  expect(out.map((o) => [o.type, o.minutes])).toEqual([["walking", 15]]);
  expect(out[0]!.basis).toContain("Dipersingkat menjadi 15 menit");
  expect(applyActivityConstraints(base, { maxMinutes: 60 }).map((o) => o.minutes)).toEqual([30, 20, 20]);
  expect(applyActivityConstraints([base[2]!], { avoidTypes: ["running"] })).toEqual([expect.objectContaining({ type: "walking", minutes: 10 })]);
});

test("Router: catat makan, lanjutan aktivitas berdasarkan konteks, dan petunjuk persetujuan", () => {
  expect(routeMessage("Tadi siang makan nasi satu piring, ayam bakar, dan lalapan", { hasPreviousRun: false })).toEqual({ kind: "MEAL_LOG" });
  expect(routeMessage("Aku pengen lebih aktif.", { hasPreviousRun: false })).toEqual({ kind: "ACTIVITY_PLAN" });
  const ctx = { hasPreviousRun: true, lastRoute: "ACTIVITY_PLAN" };
  expect(routeMessage("Tapi akhir-akhir ini sibuk.", ctx)).toEqual({ kind: "ACTIVITY_PLAN", busy: true, maxMinutes: 10 });
  expect(routeMessage("Yang 10 menit aja.", ctx)).toEqual({ kind: "ACTIVITY_PLAN", maxMinutes: 10 });
  expect(routeMessage("Oke, masukin besok pagi.", ctx)).toEqual({ kind: "APPROVAL_HINT" });
  expect(routeMessage("Oke, masukin besok pagi.", { hasPreviousRun: false })).not.toEqual({ kind: "APPROVAL_HINT" });
  expect(routeMessage("Yang 10 menit aja.", { hasPreviousRun: false }).kind).not.toBe("ACTIVITY_PLAN");
});
