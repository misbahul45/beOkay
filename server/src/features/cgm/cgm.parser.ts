export const CGM_PARSER_VERSION = "libreview-csv-v1";
export const MMOL_TO_MGDL = 18.0182;
export const CGM_MIN = 20;
export const CGM_MAX = 600;
export const MAX_CSV_ROWS = 40_000;

export type DateOrder = "MDY" | "DMY";
export type CgmKind = "HISTORIC" | "SCAN";
export type ParsedReading = { localDate: string; localTime: string; kind: CgmKind; valueMgDl: number };
export type ParseResult =
  | { ok: true; device: string | null; unit: "mg/dL" | "mmol/L"; dateOrder: DateOrder | "YMD"; total: number; skipped: number; readings: ParsedReading[] }
  | { ok: false; code: "CGM_FORMAT_UNKNOWN" | "CGM_DATE_ORDER_AMBIGUOUS" | "CGM_TOO_MANY_ROWS" | "CGM_EMPTY"; message: string };

export function splitCsvLine(line: string, sep = ","): string[] {
  const out: string[] = [];
  let cur = "";
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i]!;
    if (quoted) {
      if (ch === '"' && line[i + 1] === '"') {
        cur += '"';
        i++;
      } else if (ch === '"') quoted = false;
      else cur += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === sep) {
      out.push(cur.trim());
      cur = "";
    } else cur += ch;
  }
  out.push(cur.trim());
  return out;
}

const TS = /^(\d{1,4})[-/.](\d{1,2})[-/.](\d{1,4})[ T](\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp][Mm])?$/;
type RawTs = { a: number; b: number; c: number; h: number; mi: number; ymd: boolean };

function rawTimestamp(s: string): RawTs | null {
  const m = s.trim().match(TS);
  if (!m) return null;
  let h = Number(m[4]);
  const ampm = m[6]?.toLowerCase();
  if (ampm) {
    if (h < 1 || h > 12) return null;
    h = (h % 12) + (ampm === "pm" ? 12 : 0);
  }
  const a = Number(m[1]), b = Number(m[2]), c = Number(m[3]);
  return { a, b, c, h, mi: Number(m[5]), ymd: m[1]!.length === 4 };
}

const pad = (n: number) => String(n).padStart(2, "0");
function toLocal(t: RawTs, order: DateOrder | "YMD") {
  const [y, mo, d] = order === "YMD" ? [t.a, t.b, t.c] : order === "MDY" ? [t.c, t.a, t.b] : [t.c, t.b, t.a];
  if (y < 2000 || y > 2100 || mo < 1 || mo > 12 || d < 1 || d > 31 || t.h > 23 || t.mi > 59) return null;
  const date = `${y}-${pad(mo)}-${pad(d)}`;
  if (new Date(date + "T00:00:00Z").toISOString().slice(0, 10) !== date) return null;
  return { localDate: date, localTime: `${pad(t.h)}:${pad(t.mi)}` };
}

export function detectDateOrder(stamps: RawTs[]): DateOrder | "YMD" | "AMBIGUOUS" | "INVALID" {
  if (stamps.length && stamps.every((s) => s.ymd)) return "YMD";
  const dm = stamps.filter((s) => !s.ymd);
  const firstOver = dm.some((s) => s.a > 12);
  const secondOver = dm.some((s) => s.b > 12);
  if (firstOver && secondOver) return "INVALID";
  if (firstOver) return "DMY";
  if (secondOver) return "MDY";
  return "AMBIGUOUS";
}

function parseValue(raw: string | undefined, unit: "mg/dL" | "mmol/L"): number | null {
  if (!raw) return null;
  const n = Number(raw.replace(",", "."));
  if (!Number.isFinite(n) || n <= 0) return null;
  const mg = unit === "mmol/L" ? n * MMOL_TO_MGDL : n;
  const v = Math.round(mg * 10) / 10;
  return v >= CGM_MIN && v <= CGM_MAX ? v : null;
}

export function parseLibreView(text: string, opts: { dateOrder?: DateOrder | "auto" } = {}): ParseResult {
  const lines = text.replace(/^﻿/, "").split(/\r?\n/).filter((l) => l.trim() !== "");
  const headerAt = lines.findIndex((l) => /device timestamp/i.test(l));
  if (headerAt < 0) return { ok: false, code: "CGM_FORMAT_UNKNOWN", message: "Berkas bukan ekspor CSV LibreView (kolom Device Timestamp tidak ditemukan)." };
  const sep = lines[headerAt]!.includes(";") && !lines[headerAt]!.includes(",") ? ";" : ",";
  const header = splitCsvLine(lines[headerAt]!, sep).map((h) => h.toLowerCase());
  const col = (re: RegExp) => header.findIndex((h) => re.test(h));
  const tsCol = col(/^device timestamp$/);
  const typeCol = col(/^record type$/);
  const histCol = col(/^historic glucose/);
  const scanCol = col(/^scan glucose/);
  const deviceCol = col(/^device$/);
  if (tsCol < 0 || typeCol < 0 || (histCol < 0 && scanCol < 0)) return { ok: false, code: "CGM_FORMAT_UNKNOWN", message: "Kolom glukosa LibreView tidak lengkap." };
  const unitHeader = header[histCol >= 0 ? histCol : scanCol]!;
  const unit: "mg/dL" | "mmol/L" = /mmol/.test(unitHeader) ? "mmol/L" : "mg/dL";
  const data = lines.slice(headerAt + 1);
  if (data.length === 0) return { ok: false, code: "CGM_EMPTY", message: "Berkas tidak berisi bacaan." };
  if (data.length > MAX_CSV_ROWS) return { ok: false, code: "CGM_TOO_MANY_ROWS", message: `Berkas terlalu besar (lebih dari ${MAX_CSV_ROWS} baris). Ekspor periode yang lebih pendek.` };

  const rows = data.map((l) => splitCsvLine(l, sep));
  const glucoseRows = rows.map((r) => ({ r, type: r[typeCol], ts: rawTimestamp(r[tsCol] ?? "") })).filter((x) => (x.type === "0" || x.type === "1") && x.ts !== null);
  let order: DateOrder | "YMD";
  if (opts.dateOrder && opts.dateOrder !== "auto") order = glucoseRows.every((x) => x.ts!.ymd) ? "YMD" : opts.dateOrder;
  else {
    const d = detectDateOrder(glucoseRows.map((x) => x.ts!));
    if (d === "AMBIGUOUS") return { ok: false, code: "CGM_DATE_ORDER_AMBIGUOUS", message: "Urutan tanggal tidak bisa dipastikan. Pilih apakah tanggal ditulis hari-bulan atau bulan-hari." };
    if (d === "INVALID") return { ok: false, code: "CGM_FORMAT_UNKNOWN", message: "Format tanggal di berkas tidak konsisten." };
    order = d;
  }
  const readings: ParsedReading[] = [];
  for (const x of glucoseRows) {
    const local = toLocal(x.ts!, order);
    const kind: CgmKind = x.type === "0" ? "HISTORIC" : "SCAN";
    const value = parseValue(kind === "HISTORIC" ? x.r[histCol] : x.r[scanCol], unit);
    if (local && value !== null) readings.push({ ...local, kind, valueMgDl: value });
  }
  const device = deviceCol >= 0 ? (rows.find((r) => r[deviceCol])?.[deviceCol] ?? null) : null;
  return { ok: true, device: device ? device.slice(0, 120) : null, unit, dateOrder: order, total: rows.length, skipped: rows.length - readings.length, readings };
}
