import { expect, test } from "bun:test";
import { lockScreenText, nextOccurrence, upcomingOccurrences, type ReminderRule } from "../../src/features/reminders/reminders.model.ts";

const rule = (over: Partial<ReminderRule> = {}): ReminderRule => ({ id: "r1", kind: "glucose", localTime: "07:30", daysOfWeek: [1, 2, 3, 4, 5, 6, 7], enabled: true, ...over });

test("kejadian berikutnya hari ini bila jamnya belum lewat, kalau tidak besok (Asia/Jakarta, UTC+7)", () => {
  // 2026-11-09 00:00Z = 07:00 WIB -> 07:30 WIB = 00:30Z
  expect(nextOccurrence(rule(), "Asia/Jakarta", new Date("2026-11-09T00:00:00Z"))?.at.toISOString()).toBe("2026-11-09T00:30:00.000Z");
  expect(nextOccurrence(rule(), "Asia/Jakarta", new Date("2026-11-09T01:00:00Z"))?.at.toISOString()).toBe("2026-11-10T00:30:00.000Z");
});

test("hanya hari yang dipilih (ISO 1=Senin..7=Minggu); 2026-11-09 adalah Senin", () => {
  const onlyTueThu = rule({ daysOfWeek: [2, 4] });
  const list = upcomingOccurrences([onlyTueThu], "Asia/Jakarta", new Date("2026-11-09T00:00:00Z"), 7);
  expect(list.map((o) => o.localDate)).toEqual(["2026-11-10", "2026-11-12"]);
});

test("pengingat nonaktif tidak menghasilkan kejadian", () => {
  expect(upcomingOccurrences([rule({ enabled: false })], "Asia/Jakarta", new Date("2026-11-09T00:00:00Z"), 3)).toEqual([]);
  expect(nextOccurrence(rule({ enabled: false }), "Asia/Jakarta", new Date())).toBeNull();
});

test("DST: jam tetap sama menurut dinding saat musim berganti (America/New_York)", () => {
  // Sebelum 2026-11-01 offset -04:00 (EDT), sesudahnya -05:00 (EST); 07:30 lokal bergeser 1 jam di UTC.
  const before = nextOccurrence(rule(), "America/New_York", new Date("2026-10-31T00:00:00Z"))!;
  const after = nextOccurrence(rule(), "America/New_York", new Date("2026-11-02T00:00:00Z"))!;
  expect(before.at.toISOString()).toBe("2026-10-31T11:30:00.000Z");
  expect(after.at.toISOString()).toBe("2026-11-02T12:30:00.000Z");
  expect(before.localTime).toBe("07:30");
  expect(after.localTime).toBe("07:30");
});

test("DST celah musim semi: 02:30 yang tidak ada pada 2026-03-08 dimajukan, tetap satu kejadian hari itu", () => {
  const list = upcomingOccurrences([rule({ localTime: "02:30" })], "America/New_York", new Date("2026-03-07T12:00:00Z"), 2).filter((o) => o.localDate === "2026-03-08");
  expect(list).toHaveLength(1);
  // 02:30 tidak ada; dimajukan menjadi 03:30 EDT = 07:30Z
  expect(list[0]!.at.toISOString()).toBe("2026-03-08T07:30:00.000Z");
});

test("urutan kronologis lintas pengingat dan batas jumlah", () => {
  const rules = [rule({ id: "b", localTime: "20:00" }), rule({ id: "a", localTime: "08:00" })];
  const list = upcomingOccurrences(rules, "Asia/Jakarta", new Date("2026-11-09T00:00:00Z"), 1, 3);
  expect(list.map((o) => `${o.localDate} ${o.localTime}`)).toEqual(["2026-11-09 08:00", "2026-11-09 20:00", "2026-11-10 08:00"]);
});

test("teks layar kunci tidak memuat nama obat, nilai, atau kata sensitif", () => {
  for (const kind of ["medication", "glucose", "meal", "activity", "goal", "custom"] as const) {
    const t = lockScreenText(kind);
    expect(JSON.stringify(t).toLowerCase()).not.toMatch(/insulin|metformin|mg\/dl|diabetes|dosis|obat/);
  }
});
