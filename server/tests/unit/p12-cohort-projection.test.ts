import { describe, expect, test } from "bun:test";
import { determineJourney, filterByJourney, JOURNEY_CAPABILITIES, JOURNEYS, type JourneyInput } from "../../src/features/cohort/cohort.policy.ts";
import { EDUCATION_MODULES, MODULE_JOURNEYS } from "../../src/content/education/modules.ts";
import { strategiesFor, STRATEGIES, BARRIERS } from "../../src/features/coaching/coaching.strategies.ts";
import { aggregateDays, datesBetween, isActiveDay, isRecordedDay, unionMinutes } from "../../src/features/projections/daily-facts.model.ts";
import { MIN_ACTIVITY_MINUTES } from "../../src/features/community/scoring.model.ts";

const Y = 2026;
const j = (i: Partial<JourneyInput>) => determineJourney({ diagnosisStatus: "not_diagnosed", diabetesType: null, riskStatement: null, birthYear: 1990, ...i }, Y).journey;

describe("cohort-policy-v1", () => {
  test("matriks jalur: hanya pernyataan pengguna, tidak ada penetapan dari data", () => {
    expect(j({ diagnosisStatus: "diagnosed", diabetesType: "type_2" })).toBe("T2DM_SUPPORT");
    expect(j({ diagnosisStatus: "diagnosed", diabetesType: "type_1" })).toBe("UNDETERMINED");
    expect(j({ diagnosisStatus: "diagnosed", diabetesType: "other" })).toBe("UNDETERMINED");
    expect(j({ riskStatement: "prediabetes_told" })).toBe("PREVENTION");
    expect(j({ riskStatement: "at_risk_told" })).toBe("PREVENTION");
    expect(j({ riskStatement: "none" })).toBe("WELLNESS");
    expect(j({})).toBe("WELLNESS");
    expect(j({ diagnosisStatus: "undisclosed" })).toBe("WELLNESS");
    expect(j({ diagnosisStatus: "unknown", riskStatement: "at_risk_told" })).toBe("PREVENTION");
    expect(j({ birthYear: null, diagnosisStatus: "diagnosed", diabetesType: "type_2" })).toBe("UNDETERMINED");
    expect(j({ birthYear: Y - 17, riskStatement: "prediabetes_told" })).toBe("UNDETERMINED");
    expect(j({ birthYear: Y - 18 })).toBe("WELLNESS");
  });

  test("UNDETERMINED = pencatatan saja; WELLNESS/PREVENTION tidak menampilkan fitur glukosa/obat bawaan", () => {
    expect(JOURNEY_CAPABILITIES.UNDETERMINED).toMatchObject({ coaching: false, assistant: false, community: false });
    for (const k of ["PREVENTION", "WELLNESS"] as const) expect(JOURNEY_CAPABILITIES[k]).toMatchObject({ coaching: true, glucoseFeaturesVisible: false, medicationFeaturesVisible: false });
    expect(JOURNEY_CAPABILITIES.PREVENTION.screeningReminder).toBe(true);
    expect(filterByJourney([{ k: 1, allowedJourneys: ["PREVENTION"] as const }, { k: 2, allowedJourneys: ["WELLNESS"] as const }], "PREVENTION").map((x) => x.k)).toEqual([1]);
  });

  test("pemisahan konten: modul T2DM tidak pernah sampai ke PREVENTION/WELLNESS dan sebaliknya", () => {
    for (const m of EDUCATION_MODULES) expect(MODULE_JOURNEYS[m.key]).toBeDefined();
    const T2DM_ONLY = ["mengenal-dmt2", "hipoglikemia", "obat-bertanya-dokter", "cek-gula-mandiri", "puasa-ramadan", "saat-sakit", "perawatan-kaki"];
    for (const k of T2DM_ONLY) for (const jr of ["PREVENTION", "WELLNESS"] as const) expect(MODULE_JOURNEYS[k]).not.toContain(jr);
    expect(MODULE_JOURNEYS["cegah-diabetes"]).toEqual(["PREVENTION"]);
    for (const m of EDUCATION_MODULES.filter((m) => !MODULE_JOURNEYS[m.key]!.includes("T2DM_SUPPORT"))) expect(m.body).not.toMatch(/insulin|dosis|hipoglikemia/i);
  });

  test("strategi yang menyebut glukometer/obat hanya untuk T2DM", () => {
    for (const jr of JOURNEYS) {
      const keys = BARRIERS.flatMap((b) => strategiesFor(jr)[b].map((s) => s.key));
      if (jr === "PREVENTION" || jr === "WELLNESS") expect(keys).not.toContain("FORGOT_VISIBLE");
      else expect(keys).toContain("FORGOT_VISIBLE");
      for (const k of keys) {
        const s = BARRIERS.flatMap((b) => STRATEGIES[b]).find((x) => x.key === k)!;
        if (jr === "WELLNESS") expect(s.detail).not.toMatch(/glukometer/i);
      }
    }
  });
});

describe("daily-facts-v1", () => {
  const wib = (d: string, hh: number, mm = 0) => new Date(`${d}T${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}:00+07:00`);
  const local = (d: Date) => new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Jakarta" }).format(d);
  const dates = datesBetween("2026-11-01", "2026-11-05");

  test("agregasi per tanggal lokal, langkah null bila tidak ada, sesi lewat tengah malam UTC tetap tanggal lokal", () => {
    const f = aggregateDays(dates, {
      sessions: [
        { startedAt: wib("2026-11-01", 6), durationMinutes: 12, source: "manual" },
        { startedAt: wib("2026-11-01", 18), durationMinutes: 5, source: "health_connect" },
        { startedAt: wib("2026-11-02", 0, 30), durationMinutes: 9, source: "health_connect" },
      ],
      meals: [{ at: wib("2026-11-03", 12), category: "lunch" }, { at: wib("2026-11-03", 7), category: "breakfast" }],
      glucose: [{ at: wib("2026-11-04", 6) }],
      intakes: [{ at: wib("2026-11-04", 7) }],
      checkins: [{ at: wib("2026-11-05", 20) }],
      steps: [{ localDate: "2026-11-02", steps: 4000, source: "health_connect" }],
      sleep: [],
    }, local);
    expect(f.get("2026-11-01")).toMatchObject({ activeMinutes: 17, activeMinutesManual: 12, activeMinutesDevice: 5, sessionCount: 2, longestSessionMinutes: 12, steps: null, sleepMinutes: null });
    expect(f.get("2026-11-02")).toMatchObject({ sessionCount: 1, longestSessionMinutes: 9, steps: 4000 });
    expect(f.get("2026-11-03")).toMatchObject({ mealsLogged: 2, mealCategories: ["breakfast", "lunch"] });
    expect(f.get("2026-11-04")).toMatchObject({ glucoseChecks: 1, medicationConfirmed: 1 });
    expect(f.get("2026-11-05")).toMatchObject({ goalCheckins: 1, activeMinutes: 0, longestSessionMinutes: null });
    expect(isActiveDay(f.get("2026-11-01")!, MIN_ACTIVITY_MINUTES)).toBe(true);
    expect(isActiveDay(f.get("2026-11-02")!, MIN_ACTIVITY_MINUTES)).toBe(false);
    expect(isRecordedDay(f.get("2026-11-05")!)).toBe(false);
  });

  test("paritas dengan perhitungan komunitas lama: hari aktif = ada satu sesi >= 10 menit", () => {
    const sessions = Array.from({ length: 40 }, (_, i) => ({ startedAt: new Date(Date.UTC(2026, 10, 1) + i * 3.3 * 3_600_000), durationMinutes: (i * 7) % 25, source: i % 2 ? "manual" : "health_connect" }));
    const legacy = [...new Set(sessions.filter((s) => s.durationMinutes >= MIN_ACTIVITY_MINUTES).map((s) => local(s.startedAt)))].filter((d) => d >= "2026-11-01" && d <= "2026-11-05").sort();
    const f = aggregateDays(dates, { sessions, meals: [], glucose: [], intakes: [], checkins: [], steps: [], sleep: [] }, local);
    expect([...f.values()].filter((d) => isActiveDay(d, MIN_ACTIVITY_MINUTES)).map((d) => d.localDate)).toEqual(legacy);
  });

  test("tidur dari dua perangkat yang tumpang tindih dihitung sekali", () => {
    const a = { startedAt: new Date("2026-11-02T15:00:00Z"), endedAt: new Date("2026-11-02T22:00:00Z") };
    const b = { startedAt: new Date("2026-11-02T16:00:00Z"), endedAt: new Date("2026-11-02T23:00:00Z") };
    expect(unionMinutes([a, b])).toBe(480);
    expect(unionMinutes([a])).toBe(420);
    expect(unionMinutes([])).toBe(0);
    const f = aggregateDays(["2026-11-03"], { sessions: [], meals: [], glucose: [], intakes: [], checkins: [], steps: [], sleep: [{ ...a, durationMinutes: 420, source: "health_connect" }, { ...b, durationMinutes: 420, source: "health_connect" }] }, local);
    expect(f.get("2026-11-03")!.sleepMinutes).toBe(480);
  });
});
