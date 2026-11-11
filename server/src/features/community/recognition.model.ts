export const RECOGNITION_RULES_VERSION = "recognition-v1";

export type RecognitionFacts = {
  challengesJoined: number;
  challengesCompleted: number;
  challengesFinished: number;
  reflections: number;
  reflectionStreak: number;
  plansDone: number;
  loggingStreak: number | null;
};

export type RecognitionRule = {
  key: string;
  category: "CHALLENGE" | "REFLECTION" | "PLAN" | "LOGGING";
  title: string;
  detail: string;
  met: (f: RecognitionFacts) => boolean;
};

export const RECOGNITION_RULES: RecognitionRule[] = [
  { key: "CHALLENGE_JOINED_1", category: "CHALLENGE", title: "Tantangan pertama", detail: "Kamu ikut tantangan komunitas untuk pertama kali.", met: (f) => f.challengesJoined >= 1 },
  { key: "CHALLENGE_COMPLETED_1", category: "CHALLENGE", title: "Tantangan tuntas", detail: "Target hari aktif tantangan tercapai.", met: (f) => f.challengesCompleted >= 1 },
  { key: "CHALLENGES_FINISHED_3", category: "CHALLENGE", title: "3 tantangan diikuti", detail: "Kamu mengikuti tiga tantangan sampai selesai.", met: (f) => f.challengesFinished >= 3 },
  { key: "REFLECTION_1", category: "REFLECTION", title: "Refleksi pertama", detail: "Kamu menyelesaikan refleksi mingguan pertama.", met: (f) => f.reflections >= 1 },
  { key: "REFLECTION_STREAK_4", category: "REFLECTION", title: "4 minggu refleksi", detail: "Refleksi mingguan empat minggu berturut-turut.", met: (f) => f.reflectionStreak >= 4 },
  { key: "PLANS_DONE_5", category: "PLAN", title: "5 rencana terlaksana", detail: "Lima hari rencana kecil tercatat atau kamu konfirmasi.", met: (f) => f.plansDone >= 5 },
  { key: "LOGGING_STREAK_7", category: "LOGGING", title: "7 hari mencatat", detail: "Tujuh hari berturut-turut ada catatan.", met: (f) => (f.loggingStreak ?? 0) >= 7 },
];

export function earned(f: RecognitionFacts): RecognitionRule[] {
  return RECOGNITION_RULES.filter((r) => r.met(f));
}

export function longestStreak(dates: string[]): number {
  const days = [...new Set(dates)].sort();
  let best = 0, run = 0, prev: number | null = null;
  for (const d of days) {
    const t = Date.parse(d + "T00:00:00Z");
    run = prev !== null && t - prev === 86_400_000 ? run + 1 : 1;
    best = Math.max(best, run);
    prev = t;
  }
  return best;
}

export function weekStreak(weekStarts: string[]): number {
  const weeks = [...new Set(weekStarts)].sort();
  let best = 0, run = 0, prev: number | null = null;
  for (const w of weeks) {
    const t = Date.parse(w + "T00:00:00Z");
    run = prev !== null && t - prev === 7 * 86_400_000 ? run + 1 : 1;
    best = Math.max(best, run);
    prev = t;
  }
  return best;
}
