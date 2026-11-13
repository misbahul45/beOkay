import { describe, expect, test } from "bun:test";
import { EDUCATION_MODULES } from "../../src/content/education/modules.ts";
import { CURATED_DISHES, TOP_QUERIES } from "../../src/content/food/curated-dishes.ts";
import { SAFETY_RULE_CODES } from "../../src/features/agent/agent.safety.ts";
import { summarizeCgm } from "../../src/features/cgm/cgm.model.ts";
import { detectDateOrder, parseLibreView, splitCsvLine } from "../../src/features/cgm/cgm.parser.ts";
import { lastDays } from "../../src/features/companion/companion.summary.ts";
import { SAFETY_MODULES, contentHash, parseBody } from "../../src/features/education/education.service.ts";
import { buildFhirBundle, labMapping } from "../../src/features/export/fhir.model.ts";
import { composeDish, methodText, totalGrams, type IngredientRef } from "../../src/features/food-reference/curated.model.ts";

describe("K-4 modul edukasi", () => {
  test("modul edukasi: kunci unik, tiap modul punya beberapa bagian dan sumber", () => {
    expect(EDUCATION_MODULES.length).toBeGreaterThanOrEqual(8);
    expect(EDUCATION_MODULES.length).toBeLessThanOrEqual(16);
    expect(new Set(EDUCATION_MODULES.map((m) => m.key)).size).toBe(EDUCATION_MODULES.length);
    for (const m of EDUCATION_MODULES) {
      expect(m.key).toMatch(/^[a-z0-9][a-z0-9-]{2,59}$/);
      expect(m.readMinutes).toBeGreaterThanOrEqual(1);
      const sections = parseBody(m.body);
      expect(sections.length).toBeGreaterThanOrEqual(3);
      expect(sections.at(-1)!.heading).toBe("Sumber");
      expect(m.body.length).toBeLessThan(20000);
    }
  });

  test("modul tidak menyebut nama obat atau takaran tertentu", () => {
    const drugs = /(metformin|glimepirid|gliklazid|glibenklamid|insulin glargin|sitagliptin|empagliflozin|dapagliflozin|semaglutid|\d+\s*(mg|unit)(?![/\w]))/i;
    for (const m of EDUCATION_MODULES) expect(m.body).not.toMatch(drugs);
  });

  test("setiap kode keselamatan yang dipetakan memakai kunci modul yang ada; SELF_HARM tidak dipetakan", () => {
    const keys = new Set(EDUCATION_MODULES.map((m) => m.key));
    for (const [code, list] of Object.entries(SAFETY_MODULES)) {
      expect(SAFETY_RULE_CODES).toContain(code as never);
      for (const k of list) expect(keys.has(k)).toBe(true);
    }
    expect(SAFETY_MODULES.SELF_HARM).toBeUndefined();
  });

  test("hash isi berubah bila teks berubah dan stabil terhadap urutan topik", () => {
    const m = EDUCATION_MODULES[0]!;
    expect(contentHash(m)).toBe(contentHash({ ...m, topics: [...m.topics].reverse() }));
    expect(contentHash(m)).not.toBe(contentHash({ ...m, body: m.body + " " }));
  });

  test("parseBody memisahkan judul, paragraf, dan butir", () => {
    expect(parseBody("## A\nsatu\n- x\n- y\n\n## B\ndua")).toEqual([
      { heading: "A", paragraphs: ["satu"], bullets: ["x", "y"] },
      { heading: "B", paragraphs: ["dua"], bullets: [] },
    ]);
  });
});

describe("K-7 hidangan terkurasi", () => {
  const ref = (code: string, v: Partial<IngredientRef>): [string, IngredientRef] => [code, { id: code, code, name: code, water: 50, calories: 100, protein: 10, fat: 5, carbohydrates: 20, fiber: 1, ...v }];

  test("komposisi = jumlah gizi bahan dibagi berat total termasuk air", () => {
    const refs = new Map([ref("A", { calories: 200, carbohydrates: 40, protein: 4, fat: 0, fiber: 2, water: 50 }), ref("B", { calories: 900, carbohydrates: 0, protein: 0, fat: 100, fiber: 0, water: 0 })]);
    const dish = { code: "CUR-T", name: "Uji", serving: { min: 100, typical: 220, max: 300 }, ingredients: [["A", 200], ["B", 10]] as [string, number][], addedWaterG: 10 };
    expect(totalGrams(dish)).toBe(220);
    const c = composeDish(dish, refs);
    expect(c.ok).toBe(true);
    if (!c.ok) return;
    expect(c.per100g.calories).toBe(Math.round(((400 + 90) / 220) * 1000) / 10);
    expect(c.per100g.carbohydrates).toBe(Math.round((80 / 220) * 1000) / 10);
    expect(c.per100g.fat).toBe(Math.round((10 / 220) * 1000) / 10);
    expect(c.per100g.water).toBe(Math.round(((100 + 10) / 220) * 1000) / 10);
    expect(methodText(dish)).toContain("air/kuah 10 g");
  });

  test("nilai tak diketahui tetap NULL, bahan yang hilang menggagalkan hidangan", () => {
    const refs = new Map([ref("A", { fiber: null })]);
    const c = composeDish({ code: "CUR-T", name: "Uji", serving: { min: 1, typical: 1, max: 1 }, ingredients: [["A", 100]] }, refs);
    expect(c.ok && c.per100g.fiber).toBeNull();
    expect(composeDish({ code: "CUR-T", name: "Uji", serving: { min: 1, typical: 1, max: 1 }, ingredients: [["A", 100], ["Z", 5]] }, refs)).toEqual({ ok: false, missing: ["Z"] });
  });

  test("data kurasi: kode unik, porsi berurutan, bahan berkode TKPI, 20 kueri teratas", () => {
    expect(CURATED_DISHES.length).toBeGreaterThanOrEqual(40);
    expect(new Set(CURATED_DISHES.map((d) => d.code)).size).toBe(CURATED_DISHES.length);
    expect(new Set(CURATED_DISHES.map((d) => d.name.toLowerCase())).size).toBe(CURATED_DISHES.length);
    for (const d of CURATED_DISHES) {
      expect(d.code).toMatch(/^CUR-\d{3}$/);
      expect(d.serving.min).toBeLessThanOrEqual(d.serving.typical);
      expect(d.serving.typical).toBeLessThanOrEqual(d.serving.max);
      for (const [code, g] of d.ingredients) {
        expect(code).toMatch(/^[A-Z]{2}\d{3}$/);
        expect(g).toBeGreaterThan(0);
      }
    }
    expect(TOP_QUERIES).toHaveLength(20);
  });
});

const LIBRE_HEADER = "Device,Serial Number,Device Timestamp,Record Type,Historic Glucose mg/dL,Scan Glucose mg/dL,Non-numeric Rapid-Acting Insulin,Rapid-Acting Insulin (units),Non-numeric Food,Carbohydrates (grams),Carbohydrates (servings),Non-numeric Long-Acting Insulin,Long-Acting Insulin Value (units),Notes,Strip Glucose mg/dL,Ketone mmol/L,Meal Insulin (units),Correction Insulin (units),User Change Insulin (units)";
const row = (ts: string, type: number, hist = "", scan = "") => `FreeStyle LibreLink,ABC-123,${ts},${type},${hist},${scan},,,,,,,,,,,,,`;

describe("K-3 parser CSV LibreView", () => {
  test("format bulan-hari terdeteksi, bacaan historis dan pindaian diambil, baris lain dilewati", () => {
    const csv = ["Glucose Data,Generated on,11-12-2026 10:00 UTC,Generated by,Uji", LIBRE_HEADER, row("10-25-2026 08:00", 0, "120"), row("10-25-2026 08:15", 0, "185"), row("10-25-2026 08:20", 1, "", "190"), row("10-25-2026 09:00", 6), row("10-25-2026 09:15", 0, "LO"), row("10-26-2026 01:00", 0, "55")].join("\r\n");
    const r = parseLibreView("﻿" + csv);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r).toMatchObject({ unit: "mg/dL", dateOrder: "MDY", device: "FreeStyle LibreLink", total: 6, skipped: 2 });
    expect(r.readings).toEqual([
      { localDate: "2026-10-25", localTime: "08:00", kind: "HISTORIC", valueMgDl: 120 },
      { localDate: "2026-10-25", localTime: "08:15", kind: "HISTORIC", valueMgDl: 185 },
      { localDate: "2026-10-25", localTime: "08:20", kind: "SCAN", valueMgDl: 190 },
      { localDate: "2026-10-26", localTime: "01:00", kind: "HISTORIC", valueMgDl: 55 },
    ]);
  });

  test("hari-bulan dan mmol/L dengan koma desimal dikonversi ke mg/dL", () => {
    const header = LIBRE_HEADER.replace("Historic Glucose mg/dL", "Historic Glucose mmol/L").replace("Scan Glucose mg/dL", "Scan Glucose mmol/L");
    const r = parseLibreView([header, row("25-10-2026 08:00", 0, '"6,5"'), row("26-10-2026 08:00", 0, "10.0")].join("\n"));
    expect(r.ok && r.dateOrder).toBe("DMY");
    expect(r.ok && r.readings.map((x) => x.valueMgDl)).toEqual([117.1, 180.2]);
  });

  test("tanggal ambigu ditolak kecuali urutan dipilih; format asing ditolak", () => {
    const csv = [LIBRE_HEADER, row("03-04-2026 08:00", 0, "100")].join("\n");
    expect(parseLibreView(csv)).toMatchObject({ ok: false, code: "CGM_DATE_ORDER_AMBIGUOUS" });
    expect(parseLibreView(csv, { dateOrder: "DMY" })).toMatchObject({ ok: true, readings: [{ localDate: "2026-04-03" }] });
    expect(parseLibreView(csv, { dateOrder: "MDY" })).toMatchObject({ ok: true, readings: [{ localDate: "2026-03-04" }] });
    expect(parseLibreView("a,b,c\n1,2,3")).toMatchObject({ ok: false, code: "CGM_FORMAT_UNKNOWN" });
    expect(parseLibreView(LIBRE_HEADER)).toMatchObject({ ok: false, code: "CGM_EMPTY" });
  });

  test("tanggal tidak valid dan nilai di luar rentang teknis dilewati", () => {
    const r = parseLibreView([LIBRE_HEADER, row("2026-02-30 08:00", 0, "100"), row("2026-02-28 08:00", 0, "900"), row("2026-02-28 09:00", 0, "15"), row("2026-02-28 07:30 PM", 0, "140")].join("\n"));
    expect(r.ok && r.readings).toEqual([{ localDate: "2026-02-28", localTime: "19:30", kind: "HISTORIC", valueMgDl: 140 }]);
  });

  test("pemisah CSV menghormati tanda kutip", () => {
    expect(splitCsvLine('a,"b,c","d ""e"""')).toEqual(["a", "b,c", 'd "e"']);
    expect(detectDateOrder([])).toBe("AMBIGUOUS");
  });
});

describe("K-3 ringkasan CGM", () => {
  const at = (i: number) => new Date(Date.UTC(2026, 9, 1) + i * 15 * 60_000);
  test("rentang dihitung dari bacaan historis; cakupan dan kecukupan data", () => {
    const values = [50, 60, 100, 100, 150, 170, 200, 220, 260, 300];
    const readings = values.map((v, i) => ({ measuredAt: at(i), valueMgDl: v, kind: "HISTORIC" })).concat([{ measuredAt: at(99), valueMgDl: 40, kind: "SCAN" }]);
    const s = summarizeCgm(readings, 1);
    expect(s).toMatchObject({ kindUsed: "HISTORIC", readings: 10, coveragePct: 10.4, sufficient: false, meanMgDl: 161 });
    expect(s.bands).toEqual({ veryLow: 10, low: 10, inRange: 40, high: 20, veryHigh: 20 });
    const full = summarizeCgm(Array.from({ length: 96 }, (_, i) => ({ measuredAt: at(i), valueMgDl: 120, kind: "HISTORIC" })), 1);
    expect(full).toMatchObject({ coveragePct: 100, sufficient: true, cvPct: 0 });
    expect(summarizeCgm([{ measuredAt: at(0), valueMgDl: 90, kind: "SCAN" }], 14)).toMatchObject({ kindUsed: "SCAN", coveragePct: null, sufficient: false });
    expect(summarizeCgm([], 14)).toMatchObject({ readings: 0, bands: null });
  });
});

describe("D-6 FHIR R4", () => {
  const bundle = buildFhirBundle({
    patientId: "11111111-1111-4111-8111-111111111111",
    name: "Uji",
    generatedAt: new Date("2026-11-12T00:00:00Z"),
    glucose: [{ id: "g1", valueMgDl: 123.45, measuredAt: new Date("2026-11-11T01:00:00Z"), mealContext: "fasting", source: "manual_glucometer" }],
    labs: [{ id: "l1", test: "hba1c", value: 7.1, unit: "%", sampledAt: new Date("2026-11-01T00:00:00Z") }, { id: "l2", test: "egfr", value: 80, unit: "mL/min/1.73m2", sampledAt: new Date("2026-11-01T00:00:00Z") }],
    vitals: [{ id: "v1", kind: "blood_pressure", value: 130, value2: 85, unit: "mmHg", measuredAt: new Date("2026-11-10T00:00:00Z") }, { id: "v2", kind: "weight", value: 70.5, value2: null, unit: "kg", measuredAt: new Date("2026-11-10T00:00:00Z") }],
    steps: [{ id: "s1", localDate: new Date("2026-11-10T00:00:00Z"), steps: 6000 }],
  });
  const resources = bundle.entry.map((e) => e.resource as any);

  test("Bundle collection dengan Patient dan Observation yang lengkap", () => {
    expect(bundle).toMatchObject({ resourceType: "Bundle", type: "collection" });
    expect(resources[0]).toMatchObject({ resourceType: "Patient", id: "11111111-1111-4111-8111-111111111111" });
    const obs = resources.filter((r) => r.resourceType === "Observation");
    expect(obs).toHaveLength(6);
    for (const o of obs) {
      expect(o.status).toBe("final");
      expect(o.subject.reference).toBe("urn:uuid:11111111-1111-4111-8111-111111111111");
      expect(o.code.coding?.length || o.code.text).toBeTruthy();
      expect(o.effectiveDateTime ?? o.effectivePeriod).toBeTruthy();
      expect(o.valueQuantity ?? o.component).toBeTruthy();
      if (o.valueQuantity) expect(o.valueQuantity.system).toBe("http://unitsofmeasure.org");
    }
    for (const e of bundle.entry) expect(e.fullUrl).toBe(`urn:uuid:${(e.resource as any).id}`);
  });

  test("kode LOINC dan komponen tekanan darah", () => {
    const by = (id: string) => resources.find((r) => r.id === id);
    expect(by("g1").code.coding[0].code).toBe("41653-7");
    expect(by("g1").valueQuantity).toMatchObject({ value: 123.5, code: "mg/dL" });
    expect(by("g1").note[0].text).toBe("Konteks: puasa");
    expect(by("l1").code.coding[0].code).toBe("4548-4");
    expect(by("l2").code.coding).toBeUndefined();
    expect(by("v1").component.map((c: any) => c.code.coding[0].code)).toEqual(["8480-6", "8462-4"]);
    expect(by("v1").component[0].valueQuantity.code).toBe("mm[Hg]");
    expect(by("v2").code.coding[0].code).toBe("29463-7");
    expect(by("s1").code.coding[0].code).toBe("41950-7");
    expect(labMapping("hba1c", "mmol/mol").coding?.code).toBe("59261-8");
  });
});

test("K-8 tujuh hari terakhir berakhir hari ini", () => {
  expect(lastDays("2026-03-02", 7)).toEqual(["2026-02-24", "2026-02-25", "2026-02-26", "2026-02-27", "2026-02-28", "2026-03-01", "2026-03-02"]);
});
