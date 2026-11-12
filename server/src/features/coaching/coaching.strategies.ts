export const STRATEGY_CATALOG_VERSION = "strategy-catalog-v1";
export const STRATEGY_REVIEW_STATUS = "DRAFT_NOT_CLINICALLY_REVIEWED";

export const BARRIERS = ["TIME", "FORGOT", "ENERGY", "MOTIVATION", "OTHER"] as const;
export type Barrier = (typeof BARRIERS)[number];

export const BARRIER_LABEL: Record<Barrier, string> = { TIME: "Waktu", FORGOT: "Lupa", ENERGY: "Tenaga", MOTIVATION: "Motivasi", OTHER: "Hal lain" };

export type Strategy = { key: string; title: string; detail: string };

export const STRATEGIES: Record<Barrier, Strategy[]> = {
  TIME: [
    { key: "TIME_SPLIT", title: "Bagi jadi potongan 10 menit", detail: "Beberapa kali 10 menit di sela kegiatan tetap dihitung sebagai aktivitas." },
    { key: "TIME_ANCHOR", title: "Tempelkan ke kegiatan rutin", detail: "Misalnya jalan sebentar setelah makan siang atau mencatat sebelum mencuci piring." },
    { key: "TIME_PICK_SLOT", title: "Pilih satu jam longgar tiap pagi", detail: "Tentukan di awal hari kapan langkah kecil itu dilakukan." },
  ],
  FORGOT: [
    { key: "FORGOT_REMINDER", title: "Pasang satu pengingat", detail: "Satu pengingat di jam yang paling sering terlewat. Bisa diatur di menu Pengingat." },
    { key: "FORGOT_VISIBLE", title: "Taruh alat di tempat terlihat", detail: "Glukometer, catatan, atau botol obat di dekat tempat makan." },
    { key: "FORGOT_PAIR", title: "Catat langsung setelah makan", detail: "Buka beOkay sebelum berdiri dari meja makan." },
  ],
  ENERGY: [
    { key: "ENERGY_LIGHT", title: "Pilih versi yang ringan", detail: "Jalan santai 5 sampai 10 menit tetap berarti di hari yang melelahkan." },
    { key: "ENERGY_BEST_TIME", title: "Pakai jam saat paling segar", detail: "Pindahkan langkah kecil ke waktu ketika tenagamu paling baik." },
    { key: "ENERGY_ASK", title: "Ceritakan lelahmu ke tenaga kesehatan", detail: "Bila lelah terus berlanjut, bicarakan saat kontrol berikutnya." },
  ],
  MOTIVATION: [
    { key: "MOTIVATION_SMALLER", title: "Kecilkan langkahnya", detail: "Pilih langkah yang hampir pasti bisa dilakukan, lalu ulangi." },
    { key: "MOTIVATION_BUDDY", title: "Ajak satu orang", detail: "Keluarga atau teman yang menemani atau mengingatkan." },
    { key: "MOTIVATION_WHY", title: "Ingat alasanmu sendiri", detail: "Tulis satu kalimat tentang kenapa ini penting bagimu." },
  ],
  OTHER: [
    { key: "OTHER_ONE_THING", title: "Fokus pada satu hal minggu ini", detail: "Pilih satu kebiasaan saja dan biarkan yang lain dulu." },
    { key: "OTHER_ASK", title: "Bicarakan dengan tenaga kesehatan", detail: "Bila hambatannya berkaitan dengan kesehatan atau obat." },
  ],
};

export function findStrategy(barrier: Barrier, key: string): Strategy | null {
  return STRATEGIES[barrier]?.find((s) => s.key === key) ?? null;
}

export const STRATEGY_DAYS = 7;
