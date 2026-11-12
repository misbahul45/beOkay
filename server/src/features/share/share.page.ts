import type { ReportSummary } from "./report-summary.service.ts";

const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
const num = (v: number | null) => (v === null ? "–" : Number.isInteger(v) ? String(v) : v.toFixed(1).replace(".", ","));
const STYLE = "body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;margin:0;background:#f6f8fa;color:#171b20}main{max-width:760px;margin:0 auto;padding:24px 16px}h1{font-size:22px;margin:0 0 4px}h2{font-size:16px;margin:24px 0 8px}p{margin:4px 0;line-height:1.5}.muted{color:#566673;font-size:13px}table{width:100%;border-collapse:collapse;background:#fff;border-radius:12px;overflow:hidden}td,th{padding:8px 10px;border-bottom:1px solid #e3e8ee;text-align:left;font-size:14px;vertical-align:top}th{background:#eef2f5;font-weight:600}.note{background:#fff7e6;border-radius:12px;padding:12px;margin-top:16px}@media print{body{background:#fff}main{padding:0}}";

export const pageCsp = (nonce: string) => `default-src 'none'; style-src 'nonce-${nonce}'; img-src data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'`;

function shell(title: string, body: string, nonce: string) {
  return `<!doctype html><html lang="id"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><meta name="referrer" content="no-referrer"><title>${esc(title)}</title><style nonce="${nonce}">${STYLE}</style></head><body><main>${body}</main></body></html>`;
}

export function renderUnavailable(status: number, nonce = "") {
  const text = status === 410 ? "Tautan ini sudah kedaluwarsa atau dicabut oleh pemiliknya." : "Tautan tidak ditemukan.";
  return shell("Ringkasan beOkay", `<h1>Ringkasan beOkay</h1><p>${esc(text)}</p>`, nonce);
}

export function renderSummary(s: ReportSummary, expiresAt: Date, nonce = "") {
  const rows = (items: string[][]) => items.map((r) => `<tr>${r.map((c) => `<td>${c}</td>`).join("")}</tr>`).join("");
  const stats = s.statistics
    .filter((x) => x.state === "READY")
    .map((x) => [esc(x.label), `${esc(num(x.value))}${x.unit ? " " + esc(x.unit) : ""}`, `${esc(x.sampleCount)} ${esc(x.sampleUnit)} · data ${esc(x.coverage.daysWithData)}/${esc(x.coverage.totalDays)} hari`]);
  const body = [
    `<h1>Ringkasan catatan ${esc(s.days)} hari</h1>`,
    `<p>${esc(s.person.name)}${s.person.diabetesType ? ` · ${esc(s.person.diabetesType === "type_2" ? "Diabetes tipe 2" : s.person.diabetesType)}` : ""}${s.person.diagnosedYear ? ` · sejak ${esc(s.person.diagnosedYear)}` : ""}</p>`,
    `<p class="muted">Periode ${esc(s.period.start)} sampai ${esc(s.period.end)} · zona ${esc(s.timezone)} · dibuat ${esc(s.generatedLocal.localDate)} ${esc(s.generatedLocal.localTime)} · tautan berlaku sampai ${esc(expiresAt.toISOString().slice(0, 16).replace("T", " "))} UTC</p>`,
    `<h2>Ringkasan deskriptif</h2>`,
    stats.length ? `<table><tr><th>Ukuran</th><th>Nilai</th><th>Dasar</th></tr>${rows(stats)}</table>` : `<p>Belum cukup catatan pada periode ini.</p>`,
    s.steps.daysWithData ? `<p class="muted">Langkah harian dari perangkat: median ${esc(num(s.steps.medianSteps))} langkah dari ${esc(s.steps.daysWithData)} hari.</p>` : "",
    `<h2>Ukuran tubuh dan hasil lab terakhir</h2>`,
    s.vitals.length + s.labs.length
      ? `<table><tr><th>Jenis</th><th>Nilai</th><th>Tanggal</th></tr>${rows([...s.vitals, ...s.labs].map((v) => [esc(v.label), esc(v.value), esc(v.date)]))}</table>`
      : `<p>Belum ada yang dicatat.</p>`,
    `<h2>Obat yang dicatat pengguna</h2>`,
    s.medications.length ? `<table><tr><th>Nama</th><th>Kekuatan</th><th>Petunjuk yang dicatat</th></tr>${rows(s.medications.map((m) => [esc(m.name), esc(m.strength ?? "–"), esc(m.instructions ?? "–")]))}</table>` : `<p>Tidak ada obat aktif yang dicatat.</p>`,
    `<p class="note">${esc(s.disclaimer)}</p>`,
    `<p class="muted">${esc(s.version)}</p>`,
  ].join("");
  return shell(`Ringkasan beOkay ${s.days} hari`, body, nonce);
}
