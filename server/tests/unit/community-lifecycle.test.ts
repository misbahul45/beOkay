import { expect, test } from "bun:test";
import { completionFor, daysLeft, participantsLabel, periodsToEnsure, statusLabel, statusOn } from "../../src/features/community/lifecycle.model.ts";
import { earned, longestStreak, weekStreak, type RecognitionFacts } from "../../src/features/community/recognition.model.ts";
import { routeMessage } from "../../src/features/conversation/conversation.router.ts";

const weekly = { durationDays: 7, targetDays: 3, cadenceDays: 7, anchorDate: "2026-11-02" };
const monthly = { durationDays: 28, targetDays: 12, cadenceDays: 28, anchorDate: "2026-11-02" };

test("Periode dihitung dari tanggal jangkar eksplisit: periode berjalan dan berikutnya, tanpa celah atau tumpang tindih", () => {
  expect(periodsToEnsure(weekly, "2026-11-11")).toEqual([{ startsOn: "2026-11-09", endsOn: "2026-11-15" }, { startsOn: "2026-11-16", endsOn: "2026-11-22" }]);
  expect(periodsToEnsure(weekly, "2026-11-15")).toEqual([{ startsOn: "2026-11-09", endsOn: "2026-11-15" }, { startsOn: "2026-11-16", endsOn: "2026-11-22" }]);
  expect(periodsToEnsure(weekly, "2026-11-16")[0]).toEqual({ startsOn: "2026-11-16", endsOn: "2026-11-22" });
  expect(periodsToEnsure(monthly, "2026-11-11")).toEqual([{ startsOn: "2026-11-02", endsOn: "2026-11-29" }, { startsOn: "2026-11-30", endsOn: "2026-12-27" }]);
  expect(periodsToEnsure(weekly, "2026-10-20")).toEqual([{ startsOn: "2026-11-02", endsOn: "2026-11-08" }]);
  expect(periodsToEnsure({ ...weekly, durationDays: 5 }, "2026-11-14")).toEqual([{ startsOn: "2026-11-16", endsOn: "2026-11-20" }]);
});

test("Status, label, sisa hari, hasil, dan jumlah peserta yang dikelompokkan", () => {
  const p = { startsOn: "2026-11-09", endsOn: "2026-11-15" };
  expect([statusOn(p, "2026-11-08"), statusOn(p, "2026-11-09"), statusOn(p, "2026-11-15"), statusOn(p, "2026-11-16")]).toEqual(["SCHEDULED", "OPEN", "OPEN", "CLOSED"]);
  expect(statusLabel(p, "2026-11-08")).toBe("Mulai besok");
  expect(statusLabel(p, "2026-11-05")).toBe("Mulai 4 hari lagi");
  expect(statusLabel(p, "2026-11-11")).toBe("Berjalan · sisa 5 hari");
  expect(statusLabel(p, "2026-11-15")).toBe("Berjalan · hari terakhir");
  expect(statusLabel(p, "2026-11-16")).toBe("Selesai");
  expect([daysLeft(p, "2026-11-11"), daysLeft(p, "2026-11-20")]).toEqual([5, null]);
  expect([completionFor(3, 3, false), completionFor(2, 3, false), completionFor(5, 3, true)]).toEqual(["COMPLETED", "PARTICIPATED", "LEFT"]);
  expect([participantsLabel(0), participantsLabel(4), participantsLabel(5), participantsLabel(19), participantsLabel(20)]).toEqual(["kurang dari 5 peserta", "kurang dari 5 peserta", "5–19 peserta", "5–19 peserta", "20+ peserta"]);
});

test("Pengakuan hanya untuk usaha; rentetan harian dan mingguan", () => {
  const f: RecognitionFacts = { challengesJoined: 1, challengesCompleted: 0, challengesFinished: 1, reflections: 4, reflectionStreak: 4, plansDone: 5, loggingStreak: 6 };
  expect(earned(f).map((r) => r.key)).toEqual(["CHALLENGE_JOINED_1", "REFLECTION_1", "REFLECTION_STREAK_4", "PLANS_DONE_5"]);
  expect(earned({ ...f, loggingStreak: null }).some((r) => r.category === "LOGGING")).toBe(false);
  expect(JSON.stringify(earned({ ...f, challengesCompleted: 1, challengesFinished: 3, loggingStreak: 7 }))).not.toMatch(/glukosa|kalori|berat badan|mg\/dL/i);
  expect(longestStreak(["2026-11-01", "2026-11-02", "2026-11-03", "2026-11-05", "2026-11-03"])).toBe(3);
  expect(longestStreak([])).toBe(0);
  expect(weekStreak(["2026-10-19", "2026-10-26", "2026-11-09", "2026-11-02"])).toBe(4);
  expect(weekStreak(["2026-10-19", "2026-11-02"])).toBe(1);
});

test("Router: pertanyaan tentang tantangan diarahkan ke komunitas dengan topik yang tepat", () => {
  const r = (t: string) => routeMessage(t, { hasPreviousRun: false });
  expect(r("Tantangan apa yang bisa aku ikuti?")).toEqual({ kind: "COMMUNITY", topic: "DISCOVER" });
  expect(r("Bagaimana aturan tantangan dihitung?")).toEqual({ kind: "COMMUNITY", topic: "RULES" });
  expect(r("Gimana progres tantanganku?")).toEqual({ kind: "COMMUNITY", topic: "PROGRESS" });
  expect(r("Minggu ini aku merasa gagal.").kind).toBe("REFLECTION");
});
