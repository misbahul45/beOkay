import { expect, test } from "bun:test";
import { canonicalTerm, checkFood, normalizeTerm, type PreferenceLike } from "../../src/features/food-preferences/food-preferences.model.ts";

const pref = (term: string, kind: PreferenceLike["kind"] = "allergy"): PreferenceLike => ({
  id: term, kind, term: canonicalTerm(term), label: term, severity: kind === "allergy" || kind === "restriction" ? "strict" : "soft",
});

test("normalisasi: huruf kecil, tanpa diakritik dan tanda baca, alias ke istilah baku", () => {
  expect(normalizeTerm("  Kacang   Tanah! ")).toBe("kacang tanah");
  expect(canonicalTerm("Peanut")).toBe("kacang");
  expect(canonicalTerm("Kacang Tanah")).toBe("kacang");
  expect(canonicalTerm("Lactose")).toBe("susu");
});

test("alergi kacang: nama berisi kacang dikecualikan (NAME), hidangan lazim berbumbu kacang diduga (COMMON_INGREDIENT)", () => {
  const prefs = [pref("kacang")];
  const direct = checkFood("Selai kacang", prefs);
  expect(direct.status).toBe("EXCLUDED");
  expect(direct.matches[0]).toMatchObject({ basis: "NAME", evidence: "kacang" });
  const common = checkFood("Gado-gado", prefs);
  expect(common.status).toBe("EXCLUDED");
  expect(common.matches[0]).toMatchObject({ basis: "COMMON_INGREDIENT" });
});

test("tanpa kecocokan tidak pernah berarti aman: catatan menyatakan bahan lengkap tidak diketahui", () => {
  const r = checkFood("Nasi putih", [pref("kacang")]);
  expect(r.status).toBe("NO_MATCH_FOUND");
  expect(r.note).toContain("Bahan lengkap tidak diketahui");
  expect(JSON.stringify(r).toLowerCase()).not.toContain("aman");
});

test("tanpa kendala keras, hasil tidak menyebut bahan tidak diketahui", () => {
  const r = checkFood("Nasi putih", [pref("pedas", "dislike")]);
  expect(r.status).toBe("NO_MATCH_FOUND");
  expect(r.note).not.toContain("Bahan lengkap");
});

test("ketidaksukaan hanya memberi peringatan, tidak mengecualikan", () => {
  const r = checkFood("Sambal terasi", [pref("terasi", "dislike")]);
  expect(r.status).toBe("WARNING");
});

test("kata pendek dicocokkan sebagai kata utuh: 'mi' tidak cocok dengan 'minyak' atau 'semangka'", () => {
  const prefs = [pref("gluten")];
  expect(checkFood("Es semangka", prefs).status).toBe("NO_MATCH_FOUND");
  expect(checkFood("Minyak kelapa", prefs).status).toBe("NO_MATCH_FOUND");
  expect(checkFood("Mi goreng", prefs).status).toBe("EXCLUDED");
});

test("pembatasan halal mengecualikan babi dan alkohol; vegetarian mengecualikan daging dan ikan", () => {
  const halal = [pref("halal", "restriction")];
  expect(checkFood("Bak kut teh babi", halal).status).toBe("EXCLUDED");
  expect(checkFood("Tape singkong", halal).status).toBe("EXCLUDED");
  expect(checkFood("Tempe goreng", halal).status).toBe("NO_MATCH_FOUND");
  const veg = [pref("vegetarian", "restriction")];
  expect(checkFood("Rendang sapi", veg).status).toBe("EXCLUDED");
  expect(checkFood("Ikan bakar", veg).status).toBe("EXCLUDED");
  expect(checkFood("Gado-gado", veg).status).toBe("NO_MATCH_FOUND");
});

test("istilah bebas hanya mencocokkan kata pada nama", () => {
  const r = checkFood("Es jeruk nipis", [pref("jeruk")]);
  expect(r.status).toBe("EXCLUDED");
  expect(checkFood("Es teh", [pref("jeruk")]).status).toBe("NO_MATCH_FOUND");
});

test("merek ikut diperiksa", () => {
  expect(checkFood("Biskuit", [pref("susu")], "Susu Murni Bahagia").status).toBe("EXCLUDED");
});
