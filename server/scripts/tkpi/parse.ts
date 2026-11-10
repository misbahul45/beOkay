/**
 * Mengubah keluaran OCR Mistral (ocr_<mulai>.json per potongan 20 halaman) menjadi baris TKPI tervalidasi.
 *
 *   bun run scripts/tkpi/parse.ts <folder-ocr> <keluaran parsed.json>
 */
import { readdirSync } from "node:fs";
import { parseTkpi } from "../../src/features/food-reference/tkpi-parser.ts";

const [dir, out] = [process.argv[2], process.argv[3]];
if (!dir || !out) throw new Error("Pemakaian: bun run scripts/tkpi/parse.ts <folder-ocr> <parsed.json>");
const files = readdirSync(dir).filter((f) => /^ocr_\d+\.json$/.test(f)).sort((a, b) => Number(a.slice(4, -5)) - Number(b.slice(4, -5)));
const pages: { index: number; markdown: string }[] = [];
for (const f of files) {
  const d = (await Bun.file(`${dir}/${f}`).json()) as { pages: { index: number; markdown: string }[] };
  const start = Number(f.slice(4, -5));
  for (const p of d.pages) pages.push({ index: start + p.index, markdown: p.markdown });
}
const r = parseTkpi(pages);
const verified = r.rows.filter((x) => x.status === "verified_auto").length;
console.log(JSON.stringify({ pages: pages.length, rows: r.rows.length, verified_auto: verified, needs_review: r.rows.length - verified }));
for (const [k, s] of Object.entries(r.byChapter)) console.log(`${String(s.verified).padStart(4)} / ${String(s.total).padEnd(4)} ${k}`);
await Bun.write(out, JSON.stringify(r.rows));
