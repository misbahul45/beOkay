import { describe, expect, it } from "bun:test";
import { parseLabel } from "../../src/features/food-vision/label-parser.ts";

const perServing = `
# INFORMASI NILAI GIZI
Takaran saji 30 g
Jumlah per sajian
| Energi total | 120 kkal |
| Lemak total | 3 g | 5% |
| Lemak jenuh | 1 g | 5% |
| Protein | 6 g | 10% |
| Karbohidrat total | 18 g | 6% |
| Serat pangan | 2 g | 7% |
| Gula | 5 g |
| Natrium | 150 mg | 7% |
`;

describe("parseLabel", () => {
  it("menghitung per 100 g dari nilai per sajian (takaran saji gram)", () => {
    const r = parseLabel(perServing);
    expect(r.basis).toBe("per_serving");
    expect(r.servingGrams).toBe(30);
    expect(r.printed).toEqual({ calories: 120, fat: 3, protein: 6, carbohydrates: 18, fiber: 2 });
    expect(r.per100g.calories).toBe(400);
    expect(r.per100g.fat).toBe(10);
    expect(r.per100g.carbohydrates).toBe(60);
  });

  it("tidak mengambil lemak jenuh sebagai lemak total, dan energi dari lemak diabaikan", () => {
    const r = parseLabel("Per 100 g\nEnergi dari lemak 50 kkal\nLemak jenuh 9 g\nLemak total 12 g\nEnergi total 300 kkal");
    expect(r.printed.fat).toBe(12);
    expect(r.printed.calories).toBe(300);
    expect(r.basis).toBe("per_100g");
  });

  it("memakai kolom per 100 g saat ada dua kolom, sesuai urutan judul", () => {
    const a = parseLabel("Nutrition facts | per 100 g | per serving\nEnergy | 250 kcal | 75 kcal\nProtein | 8 g | 2.4 g");
    expect(a.basis).toBe("per_100g");
    expect(a.printed.calories).toBe(250);
    const b = parseLabel("Nutrition facts | per serving | per 100 g\nEnergy | 75 kcal | 250 kcal\nProtein | 2.4 g | 8 g");
    expect(b.printed.calories).toBe(250);
    expect(b.printed.protein).toBe(8);
  });

  it("koma desimal Indonesia dan kJ", () => {
    const r = parseLabel("per 100 g\nEnergi 1046 kJ\nProtein 7,5 g\nLemak 2,5 g");
    expect(r.printed.protein).toBe(7.5);
    expect(r.printed.calories).toBeCloseTo(250, 0);
    expect(r.flags).toContain("energy_from_kj");
  });

  it("mg dikonversi ke g", () => {
    expect(parseLabel("per 100 g\nSerat 500 mg").printed.fiber).toBe(0.5);
  });

  it("tanpa takaran saji gram: per 100 g tetap null (tidak menebak)", () => {
    const r = parseLabel("Jumlah per sajian\nEnergi 100 kkal\nProtein 3 g");
    expect(r.basis).toBe("per_serving");
    expect(r.per100g.calories).toBeNull();
    expect(r.flags).toContain("serving_size_unknown");
    expect(r.printed.calories).toBe(100);
  });

  it("takaran saji dalam ml tidak dikonversi ke gram", () => {
    const r = parseLabel("Takaran saji 250 ml\nEnergi 100 kkal");
    expect(r.servingGrams).toBeNull();
    expect(r.flags).toContain("serving_in_ml");
    expect(r.per100g.calories).toBeNull();
  });

  it("ambigu (per 100 g dan takaran saji, satu kolom): dasar tidak ditetapkan", () => {
    const r = parseLabel("Takaran saji 30 g\nNilai gizi per 100 g\nEnergi 400 kkal");
    expect(r.basis).toBe("unknown");
    expect(r.per100g.calories).toBeNull();
    expect(r.flags).toContain("basis_unclear");
  });

  it("teks tanpa gizi → semua null + flag", () => {
    const r = parseLabel("Keripik singkong rasa balado. Dibuat di Indonesia.");
    expect(Object.values(r.printed).every((v) => v === null)).toBe(true);
    expect(r.flags).toContain("no_nutrition_found");
  });

  it("persentase AKG tidak dianggap nilai gizi", () => {
    const r = parseLabel("per 100 g\nProtein 10%\n");
    expect(r.printed.protein).toBeNull();
  });
});
