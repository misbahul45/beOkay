/**
 * Parser deterministik Tabel Komposisi Pangan Indonesia (TKPI) dari markdown hasil OCR.
 *
 * OCR hanya menghasilkan teks; angka tidak dipercaya begitu saja. Sebuah baris menjadi
 * `verified_auto` hanya bila lolos pemeriksaan konsistensi internal (Atwater + jumlah proksimat).
 * Selain itu `needs_review` dan TIDAK boleh dipakai kalkulator atau agen.
 * Yang diambil hanya zat gizi makro (kolom 3–9); kolom mikro rentan bergeser saat OCR melewatkan sel.
 */

export type TkpiStatus = "verified_auto" | "needs_review";

export type TkpiValues = {
  water: number | null;
  calories: number | null;
  protein: number | null;
  fat: number | null;
  carbohydrates: number | null;
  fiber: number | null;
  ash: number | null;
};

export type TkpiRow = {
  code: string;
  name: string;
  /** Rujukan sumber nilai pada TKPI, mis. "KZGMI-2001". */
  sourceRef: string | null;
  page: number;
  chapter: string | null;
  per100g: TkpiValues;
  status: TkpiStatus;
  flags: string[];
};

export type TkpiPage = { index: number; markdown: string };

export type TkpiParseResult = {
  rows: TkpiRow[];
  byChapter: Record<string, { total: number; verified: number }>;
};

const CODE = /^[A-Z]{2}\d{3,4}$/;
const LIMITS = { water: 100, calories: 950, protein: 100, fat: 100, carbohydrates: 100, fiber: 100, ash: 100 } as const;

export function parseNumber(cell: string | undefined): number | null {
  if (cell === undefined) return null;
  const t = cell.trim().replace(",", ".");
  if (t === "" || !/^\d+(\.\d+)?$/.test(t)) return null;
  return Number(t);
}

const cells = (line: string) => line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((c) => c.trim());

/** Atwater umum: 4·protein + 9·lemak + 4·karbohidrat (KH dihitung by difference, sudah termasuk serat). */
export function atwaterEnergy(v: Pick<TkpiValues, "protein" | "fat" | "carbohydrates">): number | null {
  if (v.protein === null || v.fat === null || v.carbohydrates === null) return null;
  return v.protein * 4 + v.fat * 9 + v.carbohydrates * 4;
}

export function validateValues(v: TkpiValues): { ok: boolean; flags: string[] } {
  const flags: string[] = [];
  for (const k of Object.keys(LIMITS) as (keyof TkpiValues)[]) {
    const x = v[k];
    if (x !== null && (x < 0 || x > LIMITS[k])) flags.push(`OUT_OF_RANGE_${k.toUpperCase()}`);
  }
  if (v.calories === null || v.protein === null || v.fat === null || v.carbohydrates === null) {
    flags.push("MISSING_MACRO");
  } else {
    const calc = atwaterEnergy(v)!;
    const tolerance = Math.max(v.calories * 0.1, 12);
    if (Math.abs(calc - v.calories) > tolerance) flags.push("ATWATER_MISMATCH");
  }
  if (v.water !== null && v.ash !== null && v.protein !== null && v.fat !== null && v.carbohydrates !== null) {
    const sum = v.water + v.protein + v.fat + v.carbohydrates + v.ash;
    if (sum < 95 || sum > 105) flags.push("PROXIMATE_SUM_OFF");
  }
  return { ok: flags.length === 0, flags };
}

export function parseTkpi(pages: TkpiPage[]): TkpiParseResult {
  const rows: TkpiRow[] = [];
  const seen = new Set<string>();
  const byChapter: TkpiParseResult["byChapter"] = {};
  let chapter: string | null = null;
  let inTables = false;

  for (const page of pages) {
    for (const raw of page.markdown.split("\n")) {
      const line = raw.trim();
      const heading = /^#{1,4}\s*(\d+)\.(\d+)\.\s*(.+)$/.exec(line);
      if (heading) {
        const major = Number(heading[1]);
        inTables = major === 4;
        chapter = inTables ? `4.${heading[2]}. ${heading[3]!.replace(/\*/g, "").trim()}` : null;
        continue;
      }
      if (/^#{1,4}\s*5\.\s*INDEKS/i.test(line)) inTables = false;
      if (!inTables || !line.startsWith("|")) continue;

      const c = cells(line);
      // Tabel data punya 25 kolom; OCR kadang menghilangkan satu sel kosong (24). Tabel lain diabaikan.
      if (c.length < 24 || c.length > 25 || !CODE.test(c[0] ?? "")) continue;

      const values: TkpiValues = {
        water: parseNumber(c[3]),
        calories: parseNumber(c[4]),
        protein: parseNumber(c[5]),
        fat: parseNumber(c[6]),
        carbohydrates: parseNumber(c[7]),
        fiber: parseNumber(c[8]),
        ash: parseNumber(c[9]),
      };
      const name = (c[1] ?? "").replace(/\s+/g, " ").trim();
      const checked = validateValues(values);
      const flags = [...checked.flags];
      if (name === "") flags.push("MISSING_NAME");
      if (c.length === 24) flags.push("COLUMN_COUNT_24");
      if (seen.has(c[0]!)) flags.push("DUPLICATE_CODE");
      seen.add(c[0]!);

      // 24 kolom saja tidak membatalkan baris bila makronya lolos Atwater (sel hilang ada di ujung tabel).
      const blocking = flags.filter((f) => f !== "COLUMN_COUNT_24");
      const row: TkpiRow = {
        code: c[0]!,
        name,
        sourceRef: c[2] ? c[2] : null,
        page: page.index,
        chapter,
        per100g: values,
        status: blocking.length === 0 ? "verified_auto" : "needs_review",
        flags,
      };
      rows.push(row);
      const key = chapter ?? "—";
      const s = (byChapter[key] ??= { total: 0, verified: 0 });
      s.total += 1;
      if (row.status === "verified_auto") s.verified += 1;
    }
  }
  return { rows, byChapter };
}
