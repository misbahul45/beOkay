/**
 * Insight kontekstual: pengamatan deterministik atas catatan milik sendiri. Tidak ada penilaian nilai
 * glukosa, tidak ada prediksi, tidak ada saran medis, dan tidak ada hukuman untuk catatan yang kosong.
 * Setiap insight membawa bukti (angka yang dipakai) dan kode aturan agar dapat diperiksa.
 */
export const CONTEXTUAL_RULES_VERSION = "contextual-rules-v1";

export type ContextSnapshot = {
  localDate: string;
  localHour: number; // 0-23
  isoWeekday: number; // 1=Senin..7=Minggu
  medication: { scheduledPastDueUnknown: number; scheduledTotal: number };
  mealsToday: number;
  glucose: { totalRecords: number; daysSinceLast: number | null };
  activity: { lastWeekActiveDays: number | null; weekBeforeActiveDays: number | null };
  goals: { id: string; title: string; period: string; value: number | null; target: number }[];
  loggingStreakDays: number;
};

export type Insight = {
  code: string;
  domain: "medication" | "nutrition" | "glucose" | "activity" | "goals" | "general";
  title: string;
  body: string;
  evidence: Record<string, number | string | null>;
};

const MAX_INSIGHTS = 3;
const plural = (n: number, one: string) => `${n} ${one}`;

export function buildContextualInsights(s: ContextSnapshot): { items: Insight[]; suppressed: number; rulesVersion: string } {
  const all: Insight[] = [];

  if (s.medication.scheduledPastDueUnknown > 0) {
    all.push({
      code: "MEDICATION_UNCONFIRMED",
      domain: "medication",
      title: "Jadwal obat belum dikonfirmasi",
      body: `${plural(s.medication.scheduledPastDueUnknown, "jadwal")} hari ini sudah lewat dan belum kamu konfirmasi. Konfirmasi hanya bila memang sudah kamu lakukan; kamu juga bisa menandainya dilewati.`,
      evidence: { unconfirmed: s.medication.scheduledPastDueUnknown, scheduledToday: s.medication.scheduledTotal },
    });
  }

  if (s.mealsToday === 0 && s.localHour >= 14) {
    all.push({
      code: "NO_MEAL_LOGGED_TODAY",
      domain: "nutrition",
      title: "Belum ada catatan makan hari ini",
      body: "Kamu belum mencatat makanan hari ini. Catat bila kamu mau; melewatkannya tidak apa-apa.",
      evidence: { mealsToday: 0, localHour: s.localHour },
    });
  }

  // Tujuan mingguan: pengamatan baru dari hari Kamis agar tidak menekan di awal pekan.
  if (s.isoWeekday >= 4) {
    const behind = s.goals
      .filter((g) => g.period === "weekly" && g.target > 0 && (g.value ?? 0) / g.target < 0.5)
      .sort((a, b) => (a.value ?? 0) / a.target - (b.value ?? 0) / b.target || a.id.localeCompare(b.id))[0];
    if (behind) {
      all.push({
        code: "GOAL_BELOW_HALF",
        domain: "goals",
        title: `Tujuan "${behind.title}"`,
        body: `Sejauh ini ${behind.value ?? 0} dari target ${behind.target} pekan ini. Masih ada sisa pekan; kamu bisa menyesuaikan targetnya bila terasa terlalu berat.`,
        evidence: { value: behind.value ?? 0, target: behind.target, goalId: behind.id, weekday: s.isoWeekday },
      });
    }
  }

  // Hanya mengingatkan jarak catatan, tidak menilai angka; hanya untuk pengguna yang memang rutin mencatat.
  if (s.glucose.totalRecords >= 3 && s.glucose.daysSinceLast !== null && s.glucose.daysSinceLast >= 3) {
    all.push({
      code: "GLUCOSE_LOG_GAP",
      domain: "glucose",
      title: "Catatan glukosa terakhir",
      body: `Catatan glukosa terakhirmu ${s.glucose.daysSinceLast} hari lalu. Catat bila memang sesuai rencana pemantauan dari tenaga kesehatanmu.`,
      evidence: { daysSinceLast: s.glucose.daysSinceLast, totalRecords: s.glucose.totalRecords },
    });
  }

  if (s.loggingStreakDays >= 3) {
    all.push({
      code: "LOGGING_STREAK",
      domain: "general",
      title: `${s.loggingStreakDays} hari berturut-turut mencatat`,
      body: "Kamu konsisten mencatat. Ini tentang kebiasaanmu, bukan tentang angka kesehatanmu.",
      evidence: { streakDays: s.loggingStreakDays },
    });
  }

  if (s.activity.lastWeekActiveDays !== null && s.activity.lastWeekActiveDays > 0 && s.activity.weekBeforeActiveDays !== null && s.activity.weekBeforeActiveDays > 0) {
    all.push({
      code: "ACTIVITY_LAST_WEEK",
      domain: "activity",
      title: "Aktivitas pekan lalu",
      body: `Pekan lalu kamu mencatat aktivitas ${s.activity.lastWeekActiveDays} hari (pekan sebelumnya ${s.activity.weekBeforeActiveDays} hari). Ini hanya catatan, bukan penilaian.`,
      evidence: { lastWeekActiveDays: s.activity.lastWeekActiveDays, weekBeforeActiveDays: s.activity.weekBeforeActiveDays },
    });
  }

  return { items: all.slice(0, MAX_INSIGHTS), suppressed: Math.max(0, all.length - MAX_INSIGHTS), rulesVersion: CONTEXTUAL_RULES_VERSION };
}

/** Berapa hari berturut-turut (berakhir hari ini atau kemarin) ada paling sedikit satu catatan. */
export function loggingStreak(localDates: Iterable<string>, today: string): number {
  const set = new Set(localDates);
  const shift = (d: string, n: number) => new Date(Date.parse(d + "T00:00:00Z") + n * 86_400_000).toISOString().slice(0, 10);
  let cursor = set.has(today) ? today : shift(today, -1);
  let n = 0;
  while (set.has(cursor)) {
    n++;
    cursor = shift(cursor, -1);
  }
  return n;
}
