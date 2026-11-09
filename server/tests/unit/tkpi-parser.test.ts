import { describe, expect, it } from "bun:test";
import { atwaterEnergy, parseNumber, parseTkpi, validateValues } from "../../src/features/food-reference/tkpi-parser.ts";

const pad = (n: number) => Array(n).fill("").join(" | ");
const row = (code: string, name: string, src: string, vals: string[], total = 25) => {
  const base = [code, name, src, ...vals];
  while (base.length < total) base.push("");
  return `| ${base.join(" | ")} |`;
};

const page = (md: string, index = 1) => ({ index, markdown: md });

describe("parseNumber", () => {
  it("menerima desimal titik/koma dan menolak sel kosong, tanda, atau teks", () => {
    expect(parseNumber("12.5")).toBe(12.5);
    expect(parseNumber("12,5")).toBe(12.5);
    expect(parseNumber("")).toBeNull();
    expect(parseNumber("-")).toBeNull();
    expect(parseNumber("tr")).toBeNull();
    expect(parseNumber(undefined)).toBeNull();
  });
});

describe("validateValues", () => {
  it("menerima baris yang konsisten dengan Atwater dan jumlah proksimat", () => {
    // Dodol Banjarmasin: 2.6*4 + 8.6*9 + 70*4 = 367.8 ≈ 368
    const r = validateValues({ water: 17.3, calories: 368, protein: 2.6, fat: 8.6, carbohydrates: 70, fiber: 0.5, ash: 1.5 });
    expect(r.ok).toBe(true);
    expect(atwaterEnergy({ protein: 2.6, fat: 8.6, carbohydrates: 70 })).toBeCloseTo(367.8, 1);
  });

  it("menolak energi yang tidak cocok dengan makronutrien (mis. OCR salah baca)", () => {
    const r = validateValues({ water: 10, calories: 339, protein: 8, fat: 5, carbohydrates: 3, fiber: null, ash: 1 });
    expect(r.ok).toBe(false);
    expect(r.flags).toContain("ATWATER_MISMATCH");
  });

  it("menandai makro hilang dan nilai di luar rentang", () => {
    const r = validateValues({ water: null, calories: 100, protein: null, fat: 1, carbohydrates: 1, fiber: null, ash: null });
    expect(r.flags).toContain("MISSING_MACRO");
    const o = validateValues({ water: null, calories: 1200, protein: 1, fat: 1, carbohydrates: 1, fiber: null, ash: null });
    expect(o.flags).toContain("OUT_OF_RANGE_CALORIES");
  });

  it("menolak jumlah proksimat yang jauh dari 100 g", () => {
    const r = validateValues({ water: 50, calories: 100, protein: 5, fat: 2, carbohydrates: 15.5, fiber: null, ash: 20 });
    expect(r.flags).toContain("PROXIMATE_SUM_OFF");
  });
});

describe("parseTkpi", () => {
  const md = `
# 4.3. KACANG, BIJI, BEAN DAN HASIL OLAHANNYA

| KODE | NAMA BAHAN | SUMBER | KOMPOSISI ZAT GIZI |
${row("CP023", "Dodol banjarmasin", "KZGMI-2001", ["17.3", "368", "2.6", "8.6", "70.0", "0.5", "1.5"])}
${row("CP024", "Emping (kerupuk melinjo)", "DABM-1964", ["15.0", "300", "12.0", "1.5", "61.0", "", "28.0"])}
${row("AP022", "Mi kering", "KZGMI-2001", ["12.0", "339", "8.0", "5.0", "3.0", "", "1.0"])}
${row("AP059", "Kempur", "KZGMI-2001", ["3.5", "580", "4.8", "39.6", "51.1", "", "1.0"], 24)}
${row("CP023", "Duplikat", "KZGMI-2001", ["17.3", "368", "2.6", "8.6", "70.0", "0.5", "1.5"])}
| ZZ001 | Bukan data | x |
`;

  it("memisahkan baris lolos dan perlu ditinjau, beserta bab dan halaman", () => {
    const r = parseTkpi([page(md, 30)]);
    const by = Object.fromEntries(r.rows.map((x, i) => [i, x]));
    expect(r.rows.map((x) => x.code)).toEqual(["CP023", "CP024", "AP022", "AP059", "CP023"]);
    expect(by[0]!.status).toBe("verified_auto");
    expect(by[0]!.page).toBe(30);
    expect(by[0]!.chapter).toBe("4.3. KACANG, BIJI, BEAN DAN HASIL OLAHANNYA");
    expect(by[0]!.sourceRef).toBe("KZGMI-2001");
    // Emping: 12*4 + 1.5*9 + 61*4 = 305.5 vs 300 → lolos; abu 28 → jumlah proksimat 117.5 → perlu ditinjau
    expect(by[1]!.status).toBe("needs_review");
    expect(by[1]!.flags).toContain("PROXIMATE_SUM_OFF");
    expect(by[2]!.status).toBe("needs_review");
    expect(by[2]!.flags).toContain("ATWATER_MISMATCH");
  });

  it("baris 24 kolom tetap lolos bila makronya konsisten, dan kode ganda ditinjau", () => {
    const r = parseTkpi([page(md)]);
    const kempur = r.rows.find((x) => x.code === "AP059")!;
    expect(kempur.flags).toContain("COLUMN_COUNT_24");
    expect(kempur.status).toBe("verified_auto");
    const dup = r.rows[4]!;
    expect(dup.flags).toContain("DUPLICATE_CODE");
    expect(dup.status).toBe("needs_review");
  });

  it("mengabaikan tabel di luar bab 4 (indeks, glosari) dan menghitung per bab", () => {
    const outside = `
## 5. INDEKS
${row("CP999", "Dalam indeks", "x", ["1", "1", "1", "1", "1"])}
`;
    const r = parseTkpi([page(md), page(outside)]);
    expect(r.rows.some((x) => x.code === "CP999")).toBe(false);
    const stats = r.byChapter["4.3. KACANG, BIJI, BEAN DAN HASIL OLAHANNYA"]!;
    expect(stats.total).toBe(5);
    expect(stats.verified).toBe(2);
  });
});
