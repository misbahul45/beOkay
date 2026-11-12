export const WHY_VERSION = "why-stats-v1";

export type ActivityWhyFacts = { activeDays7: number; sessions28: number; longestMinutes: number | null; shortestMinutes: number | null };

const pct = (a: number, b: number) => Math.round((a / b) * 100);

export function activityWhy(name: string, minutes: number, f: ActivityWhyFacts): string {
  const parts: string[] = [];
  parts.push(f.activeDays7 > 0 ? `Dalam 7 hari terakhir kamu tercatat aktif ${f.activeDays7} hari.` : "Dalam 7 hari terakhir belum ada aktivitas yang tercatat.");
  if (f.longestMinutes && f.shortestMinutes && f.sessions28 >= 2) {
    parts.push(`${name} ${minutes} menit sekitar ${pct(minutes, f.longestMinutes)}% dari sesi terpanjangmu (${f.longestMinutes} menit) dan ${minutes <= f.shortestMinutes ? "tidak lebih lama dari" : `${pct(minutes, f.shortestMinutes)}% dari`} sesi terpendekmu (${f.shortestMinutes} menit) dalam 28 hari.`);
  } else if (f.longestMinutes) {
    parts.push(`${name} ${minutes} menit tidak melebihi sesi terpanjangmu (${f.longestMinutes} menit) dalam 28 hari.`);
  } else {
    parts.push(`${name} ${minutes} menit dipilih sebagai langkah awal yang pendek karena belum ada sesi tercatat dalam 28 hari.`);
  }
  return parts.join(" ");
}
