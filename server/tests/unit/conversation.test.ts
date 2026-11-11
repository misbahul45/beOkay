import { expect, test } from "bun:test";
import { identityMatch } from "../../src/features/agent/food-identity.ts";
import { statisticsReply } from "../../src/features/conversation/conversation.parts.ts";
import { foodQuery, routeMessage } from "../../src/features/conversation/conversation.router.ts";
import { NUTRIENTS, buildStatistics, type StatDay } from "../../src/features/insights/statistics.model.ts";

const r = (t: string, hasPreviousRun = false) => routeMessage(t, { hasPreviousRun });

test("Router: sapaan, terima kasih, dukungan, bantuan", () => {
  expect(r("halo")).toEqual({ kind: "GREETING" });
  expect(r("Hai beOkay!")).toEqual({ kind: "GREETING" });
  expect(r("selamat pagi")).toEqual({ kind: "GREETING" });
  expect(r("makasih ya")).toEqual({ kind: "THANKS" });
  expect(r("Aku susah konsisten")).toEqual({ kind: "SUPPORT" });
  expect(r("lagi males olahraga")).toEqual({ kind: "SUPPORT" });
  expect(r("kamu bisa apa?")).toEqual({ kind: "HELP" });
});

test("Router: sapaan diikuti permintaan diteruskan ke permintaannya", () => {
  expect(r("halo, aktivitasku minggu ini gimana?")).toEqual({ kind: "STATS", domain: "activity", days: 7 });
  expect(r("hai, cari info nasi goreng")).toEqual({ kind: "FOOD", query: "nasi goreng" });
});

test("Router: pertanyaan ringkasan per domain dan periode", () => {
  expect(r("aktivitasku minggu ini gimana?")).toEqual({ kind: "STATS", domain: "activity", days: 7 });
  expect(r("Bagaimana aktivitasku minggu ini?")).toEqual({ kind: "STATS", domain: "activity", days: 7 });
  expect(r("gula darahku sebulan terakhir")).toEqual({ kind: "STATS", domain: "glucose", days: 30 });
  expect(r("berapa kali aku cek glukosa 2 minggu ini")).toEqual({ kind: "STATS", domain: "glucose", days: 14 });
  expect(r("obatku minggu ini gimana")).toEqual({ kind: "STATS", domain: "medication", days: 7 });
  expect(r("kalori saya rata-rata berapa")).toEqual({ kind: "STATS", domain: "nutrition", days: 7 });
  expect(r("Bagaimana catatanku minggu ini?")).toEqual({ kind: "STATS", domain: "logging", days: 7 });
});

test("Router: makanan, aktivitas, dan klarifikasi", () => {
  expect(r("berapa kalori nasi goreng")).toEqual({ kind: "FOOD", query: "nasi goreng" });
  expect(r("Cari info nasi goreng")).toEqual({ kind: "FOOD", query: "nasi goreng" });
  expect(r("alternatif pengganti nasi goreng dong")).toEqual({ kind: "FOOD", query: "nasi goreng" });
  expect(r("Ide olahraga ringan 15 menit")).toEqual({ kind: "ACTIVITY_PLAN" });
  expect(r("aku mau olahraga 15 menit")).toEqual({ kind: "ACTIVITY_PLAN" });
  expect(r("makan apa ya hari ini")).toEqual({ kind: "CLARIFY_FOOD" });
  expect(r("rekomendasi menu dong")).toEqual({ kind: "CLARIFY_FOOD" });
});

test("Router: teks pendek tanpa petunjuk diuji ke katalog; kalimat panjang tidak", () => {
  expect(r("nasi goreng")).toEqual({ kind: "UNKNOWN", probe: "nasi goreng" });
  expect(r("gendar goreng enak gak?")).toEqual({ kind: "UNKNOWN", probe: "gendar goreng" });
  expect(r("hari ini aku merasa biasa saja dan agak bingung harus mulai dari mana ya")).toEqual({ kind: "UNKNOWN", probe: null });
});

test("Router: lanjutan hanya bila ada run sebelumnya", () => {
  expect(r("Kenapa ini disarankan?", true)).toEqual({ kind: "FOLLOW_UP", follow: "WHY" });
  expect(r("Ada pilihan lain?", true)).toEqual({ kind: "FOLLOW_UP", follow: "MORE" });
  expect(r("Kenapa ini disarankan?", false)).toEqual({ kind: "NO_CONTEXT" });
  expect(r("ada pilihan lain?", false)).toEqual({ kind: "NO_CONTEXT" });
});

test("Router: keselamatan selalu didahulukan", () => {
  const harm = r("aku ingin mati saja");
  expect(harm).toMatchObject({ kind: "SAFETY", code: "SELF_HARM", urgent: true });
  expect(r("halo, boleh naikkan dosis metformin?")).toMatchObject({ kind: "SAFETY", code: "MEDICATION_ADVICE", urgent: false });
  expect(r("nyeri dada setelah makan nasi goreng")).toMatchObject({ kind: "SAFETY", code: "URGENT_SYMPTOM", urgent: true });
  expect(r("aku sedih, tolong naikkan insulin")).toMatchObject({ kind: "SAFETY" });
});

test("foodQuery membuang kata tanya dan isian", () => {
  expect(foodQuery("berapa kalori tempe goreng ya?")).toBe("tempe goreng");
  expect(foodQuery("info gizi dong")).toBeNull();
});

test("Identitas makanan: kepala kata wajib cocok; cocok sebagian hanya bila ≥ separuh", () => {
  expect(identityMatch("nasi goreng", "Nasi goreng")).toBe("EXACT");
  expect(identityMatch("nasi goreng", "Nasi goreng ayam")).toBe("EXACT");
  expect(identityMatch("nasi goreng", "Nasi uduk")).toBe("CLOSE");
  expect(identityMatch("nasi goreng", "Ayam, usus, goreng")).toBeNull();
  expect(identityMatch("nasi goreng", "Gendar goreng")).toBeNull();
  expect(identityMatch("tempe", "Tempe kedelai murni, mentah")).toBe("EXACT");
  expect(identityMatch("tempe", "Tempeh")).toBe("EXACT");
  expect(identityMatch("zeltuk", "Zeltuk tahu kukus")).toBe("EXACT");
  expect(identityMatch("tahu", "Tahu-tahuan")).toBe("EXACT");
  expect(identityMatch("ayam bakar madu", "Ayam goreng")).toBeNull();
  expect(identityMatch("ayam bakar madu", "Ayam bakar")).toBe("CLOSE");
});

const day = (date: string, minutes: number | null): StatDay => ({
  date,
  isoWeekday: 1,
  meals: 0,
  nutrients: Object.fromEntries(NUTRIENTS.map((n) => [n, { value: null, knownItems: 0, totalItems: 0 }])) as StatDay["nutrients"],
  activityMinutes: minutes,
  activitySessions: minutes ? 1 : 0,
  glucose: [],
  med: { scheduled: 0, taken: 0, skipped: 0 },
});
const dates = Array.from({ length: 14 }, (_, i) => `2026-11-${String(i + 1).padStart(2, "0")}`);

test("Balasan statistik aktivitas: angka dari stats, pembanding, dan ajakan bila ada hari kosong", () => {
  const minutes = [30, 30, 30, 15, null, null, null, 30, null, 30, null, 20, null, null];
  const s = buildStatistics(dates.map((d, i) => day(d, minutes[i]!)), { glucoseUnit: "mg/dL", computedAt: new Date("2026-11-14T12:00:00Z") });
  const parts = statisticsReply("activity", 7, s.statistics, "mg/dL");
  expect(parts[0]).toEqual({ type: "text", text: "Dalam 7 hari terakhir kamu mencatat 80 menit aktivitas di 3 hari. Itu 25 menit lebih sedikit dari 7 hari sebelumnya." });
  expect(parts[1]).toMatchObject({ type: "statistic", statisticId: "activity.total_minutes", value: 80, unit: "menit", caption: "3 hari ada catatan", days: 7 });
  expect(parts.some((p) => p.type === "suggestions")).toBe(true);
  expect(parts.at(-1)).toEqual({ type: "link", label: "Lihat tren", target: "INSIGHTS" });
  expect(JSON.stringify(parts)).not.toContain("stats-v1");
});

test("Balasan statistik tanpa data tidak mengarang angka", () => {
  const s = buildStatistics(dates.map((d) => day(d, null)), { glucoseUnit: "mg/dL", computedAt: new Date("2026-11-14T12:00:00Z") });
  for (const domain of ["activity", "glucose", "nutrition", "medication", "logging"] as const) {
    const parts = statisticsReply(domain, 7, s.statistics, "mg/dL");
    expect(parts.some((p) => p.type === "statistic")).toBe(false);
    expect(parts[0]!.type).toBe("text");
  }
});
