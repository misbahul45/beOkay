/**
 * Skor tantangan `score-v1` (hipotesis produk, BUKAN metrik kesehatan tervalidasi).
 *   50 poin  = hari aktif (sesi aktivitas tercatat >= 10 menit), proporsional terhadap target hari; hari di atas target tidak menambah
 *   30 poin  = check-in kebiasaan sukarela, proporsional terhadap panjang periode
 *   20 poin  = partisipasi (sekali, setelah ada satu hari terhitung)
 * Satu hari dihitung sekali; hari istirahat tidak mengurangi skor; tidak ada poin untuk intensitas, durasi di atas minimum, atau nilai kesehatan.
 * Skor tidak pernah turun karena "kegagalan"; hanya turun lewat pembalikan ketika sumbernya dikoreksi/diarsipkan.
 */
export const SCORING_VERSION = "score-v1";
export const MIN_ACTIVITY_MINUTES = 10;
export const MAX_BACKFILL_DAYS = 2;
/** Kohort minimum agar daftar peringkat ditampilkan. Nilai provisional: perlu ditinjau, tidak menjamin anonimitas. */
export const MIN_COHORT = 5;

export type EventType = "ACTIVITY_DAY" | "CHECKIN_DAY" | "PARTICIPATION";
export type Desired = { eventType: EventType; baseKey: string; localDate: string | null; points: number; reason: string };
export type Existing = { id: string; eventType: string; sourceKey: string; points: number; reversalOf: string | null };

export const round4 = (n: number) => Math.round(n * 10_000) / 10_000;

export function desiredEvents(input: { targetDays: number; periodDays: number; activityDays: string[]; checkinDays: string[] }): Desired[] {
  const act = [...new Set(input.activityDays)].sort().slice(0, input.targetDays); // di atas target tidak menambah
  const chk = [...new Set(input.checkinDays)].sort().slice(0, input.periodDays);
  const out: Desired[] = [
    ...act.map((d) => ({ eventType: "ACTIVITY_DAY" as const, baseKey: `day:${d}`, localDate: d, points: round4(50 / input.targetDays), reason: "Hari aktif tercatat" })),
    ...chk.map((d) => ({ eventType: "CHECKIN_DAY" as const, baseKey: `checkin:${d}`, localDate: d, points: round4(30 / input.periodDays), reason: "Check-in kebiasaan" })),
  ];
  if (out.length > 0) out.push({ eventType: "PARTICIPATION", baseKey: "participation", localDate: null, points: 20, reason: "Partisipasi" });
  return out;
}

/**
 * Rekonsiliasi buku besar dengan keadaan yang diinginkan. Aktif = baris asli yang belum dibalik.
 * - yang diinginkan tetapi tidak aktif → tambah baris asli (kunci diberi akhiran #n bila pernah dibalik)
 * - yang aktif tetapi tidak lagi diinginkan → tambah baris pembalikan (poin negatif)
 * Idempoten: menjalankannya lagi pada keadaan yang sama tidak menghasilkan perubahan.
 */
export function reconcile(existing: Existing[], desired: Desired[]) {
  const originals = existing.filter((e) => e.reversalOf === null);
  const reversed = new Set(existing.filter((e) => e.reversalOf !== null).map((e) => e.reversalOf!));
  const active = originals.filter((o) => !reversed.has(o.id));
  const baseOf = (k: string) => k.replace(/#\d+$/, "");
  const activeBases = new Set(active.map((a) => `${a.eventType}|${baseOf(a.sourceKey)}`));
  const wanted = new Set(desired.map((d) => `${d.eventType}|${d.baseKey}`));
  const toAdd = desired
    .filter((d) => !activeBases.has(`${d.eventType}|${d.baseKey}`))
    .map((d) => {
      const prior = originals.filter((o) => o.eventType === d.eventType && baseOf(o.sourceKey) === d.baseKey).length;
      return { ...d, sourceKey: prior === 0 ? d.baseKey : `${d.baseKey}#${prior + 1}` };
    });
  const toReverse = active.filter((a) => !wanted.has(`${a.eventType}|${baseOf(a.sourceKey)}`));
  return { toAdd, toReverse };
}

export function totalScore(events: { points: number }[]): number {
  return Math.round(events.reduce((s, e) => s + e.points, 0) * 10) / 10;
}

/** Peringkat kompetisi standar (1,2,2,4). Seri berbagi peringkat; urutan tampilan stabil menurut alias. */
export function rank<T extends { score: number; alias: string }>(rows: T[]): (T & { rank: number })[] {
  const sorted = [...rows].sort((a, b) => b.score - a.score || a.alias.localeCompare(b.alias));
  return sorted.map((r, i) => ({ ...r, rank: i > 0 && sorted[i - 1]!.score === r.score ? 0 : i + 1 })).reduce<(T & { rank: number })[]>((acc, r, i) => [...acc, { ...r, rank: r.rank === 0 ? acc[i - 1]!.rank : r.rank }], []);
}

const BAD_ALIAS = /(admin|moderator|beokay|official|support)/i;
/** Alias publik: tidak berisi surel, nomor telepon, atau kata yang menyamar sebagai staf. */
export function aliasProblem(alias: string): string | null {
  if (!/^[A-Za-z0-9][A-Za-z0-9 _.-]{2,19}$/.test(alias)) return "Alias 3–20 karakter: huruf, angka, spasi, titik, garis bawah, atau strip.";
  if (/@/.test(alias) || /\d{6,}/.test(alias.replace(/[ .-]/g, ""))) return "Alias tidak boleh berisi surel atau nomor telepon.";
  if (BAD_ALIAS.test(alias)) return "Alias ini tidak tersedia.";
  return null;
}
export const aliasKey = (alias: string) => alias.trim().toLowerCase().replace(/\s+/g, " ");
