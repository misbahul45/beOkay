import type { CompanionSummary } from "./companion.summary.ts";

const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
const STYLE = "body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;margin:0;background:#f6f8fa;color:#171b20}main{max-width:560px;margin:0 auto;padding:24px 16px}h1{font-size:22px;margin:0 0 4px}h2{font-size:16px;margin:24px 0 8px}p{margin:4px 0;line-height:1.5}.muted{color:#566673;font-size:13px}.card{background:#fff;border-radius:16px;padding:16px}.row{display:flex;justify-content:space-between;padding:6px 0;border-bottom:1px solid #e3e8ee;font-size:15px}.row:last-child{border-bottom:0}ul{margin:4px 0;padding-left:20px}li{margin:2px 0}.note{background:#fff7e6;border-radius:12px;padding:12px;margin-top:16px;font-size:13px}";
const DAYS = ["Minggu", "Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu"];
const dayLabel = (iso: string) => `${DAYS[new Date(iso + "T00:00:00Z").getUTCDay()]} ${Number(iso.slice(8, 10))}/${Number(iso.slice(5, 7))}`;

function shell(title: string, body: string, nonce: string) {
  return `<!doctype html><html lang="id"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><meta name="referrer" content="no-referrer"><title>${esc(title)}</title><style nonce="${nonce}">${STYLE}</style></head><body><main>${body}</main></body></html>`;
}

export function renderCompanionUnavailable(status: number, nonce = "") {
  const text = status === 410 ? "Tautan pendamping ini sudah kedaluwarsa atau dicabut." : "Tautan tidak ditemukan.";
  return shell("Ringkasan pendamping beOkay", `<h1>Ringkasan pendamping</h1><p>${esc(text)}</p>`, nonce);
}

export function renderCompanion(s: CompanionSummary, nonce = "") {
  const rows = [
    ["Hari dengan catatan", `${s.daysWithRecords} dari ${s.totalDays}`],
    ["Menit aktivitas", `${s.activityMinutes} menit`],
    ["Pemeriksaan gula darah", `${s.glucoseChecks} kali`],
    ["Obat dikonfirmasi", s.medication.scheduled ? `${s.medication.confirmedTaken} dari ${s.medication.scheduled}` : "Tidak ada jadwal"],
  ];
  const body = [
    `<h1>Ringkasan 7 hari</h1>`,
    `<p class="muted">${esc(s.period.start)} sampai ${esc(s.period.end)} · zona ${esc(s.timezone)}</p>`,
    `<div class="card">${rows.map(([l, v]) => `<div class="row"><span>${esc(l)}</span><strong>${esc(v)}</strong></div>`).join("")}</div>`,
    `<h2>Pengingat obat yang belum dikonfirmasi</h2>`,
    s.medication.unconfirmed.length ? `<ul>${s.medication.unconfirmed.map((u) => `<li>${esc(dayLabel(u.localDate))}, pukul ${esc(u.localTime)}</li>`).join("")}</ul>` : `<p>Tidak ada.</p>`,
    `<p class="note">${esc(s.notice)} Dibagikan oleh pengguna beOkay dan bisa dicabut kapan saja.</p>`,
    `<p class="muted">${esc(s.version)}</p>`,
  ].join("");
  return shell("Ringkasan pendamping beOkay", body, nonce);
}
