import { SAFETY_POLICY_VERSION, explanationIsSafe } from "./agent.safety.ts";
import { executeTool, type ToolContext } from "./agent.tools.ts";
import { PERSONALIZATION_RULES_VERSION, type Profile } from "./personalization.ts";

/**
 * Graf aktivitas adaptif. Aturan keselamatan yang tertanam di kandidat:
 *  - durasi yang ditawarkan TIDAK PERNAH melebihi sesi terpanjang yang sudah pernah kamu catat (tidak ada eskalasi);
 *  - tanpa riwayat: hanya satu opsi awal singkat, ditandai data kurang;
 *  - jenis hanya yang sudah kamu lakukan (atau jalan kaki bila belum ada); tidak ada intensitas yang ditentukan aplikasi;
 *  - tidak ada kalori, target denyut jantung, atau klaim kesehatan.
 */
export type SessionLite = { type: string; minutes: number; at: string; source: string };
export type ActivityCandidate = { key: string; type: string; minutes: number; title: string; basis: string; rank: number };

const LABEL: Record<string, string> = { walking: "Jalan kaki", cycling: "Bersepeda", running: "Lari", strength: "Latihan kekuatan", other: "Aktivitas lain" };
const median = (xs: number[]) => (xs.length ? [...xs].sort((a, b) => a - b)[Math.floor((xs.length - 1) / 2)]! : 0);
const clamp = (n: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, n));
const roundTo5 = (n: number) => Math.max(5, Math.round(n / 5) * 5);

export type ActivityOutcome = {
  events: { type: string; payload: Record<string, unknown> }[];
  offered: ActivityCandidate[];
  coverage: "NONE" | "SPARSE" | "OK";
  sessions: number;
  deviceSessions: number;
  goals: { title: string; goalType: string }[];
  profileVersion: number;
};

/** Murni dan deterministik: dari riwayat ke maksimal 3 kandidat yang tidak melebihi riwayat. */
export function buildActivityCandidates(sessions: SessionLite[]): { candidates: ActivityCandidate[]; coverage: ActivityOutcome["coverage"] } {
  if (sessions.length === 0) {
    return { coverage: "NONE", candidates: [{ key: "start:walking:10", type: "walking", minutes: 10, title: `${LABEL.walking} 10 menit (mulai pelan)`, basis: "Belum ada riwayat aktivitas, jadi ini hanya contoh awal yang singkat. Sesuaikan dengan kemampuanmu.", rank: 1 }] };
  }
  const byType = new Map<string, number[]>();
  for (const s of sessions) byType.set(s.type, [...(byType.get(s.type) ?? []), s.minutes]);
  const types = [...byType.entries()].sort((a, b) => b[1].length - a[1].length || a[0].localeCompare(b[0]));
  const [topType, topMinutes] = types[0]!;
  const cap = Math.max(...topMinutes); // tidak pernah melebihi sesi terpanjang jenis ini
  const typical = clamp(roundTo5(median(topMinutes)), 5, cap);
  const out: ActivityCandidate[] = [{ key: `same:${topType}:${typical}`, type: topType, minutes: typical, title: `${LABEL[topType] ?? topType} ${typical} menit`, basis: `Sama seperti yang paling sering kamu catat (${topMinutes.length} sesi, biasanya sekitar ${typical} menit).`, rank: 1 }];
  const shorter = clamp(roundTo5(typical * 0.66), 5, typical);
  if (shorter < typical) out.push({ key: `short:${topType}:${shorter}`, type: topType, minutes: shorter, title: `${LABEL[topType] ?? topType} ${shorter} menit (versi singkat)`, basis: "Versi lebih singkat untuk hari yang sibuk atau kurang bertenaga.", rank: 2 });
  if (types[1]) {
    const [t2, m2] = types[1];
    const mins = clamp(roundTo5(median(m2)), 5, Math.max(...m2));
    out.push({ key: `alt:${t2}:${mins}`, type: t2, minutes: mins, title: `${LABEL[t2] ?? t2} ${mins} menit`, basis: `Variasi dari aktivitas lain yang pernah kamu catat (${m2.length} sesi).`, rank: 3 });
  }
  return { coverage: sessions.length >= 4 ? "OK" : "SPARSE", candidates: out.slice(0, 3) };
}

export async function runActivityGraph(ctx: ToolContext, excludeKeys: ReadonlySet<string> = new Set()): Promise<ActivityOutcome> {
  const events: ActivityOutcome["events"] = [];
  const step = (type: string, payload: Record<string, unknown> = {}) => events.push({ type, payload });
  step("NODE_ENTER", { node: "gather_context" });
  const history = await executeTool<{ sessions: SessionLite[]; deviceSessions: number }>(ctx, "get_activity_context", {});
  const goals = await executeTool<{ title: string; goalType: string }[]>(ctx, "get_behavior_goals", {});
  const profile = await executeTool<Profile>(ctx, "get_personalization", {});
  step("CONTEXT_READY", { sessions: history.sessions.length, deviceSessions: history.deviceSessions, goals: goals.length, profileVersion: profile.version });
  step("NODE_ENTER", { node: "build_candidates" });
  const built = buildActivityCandidates(history.sessions);
  const candidates = built.candidates.filter((c) => !excludeKeys.has(c.key));
  const coverage = built.coverage;
  step("CANDIDATES_BUILT", { count: candidates.length, coverage, alreadyOffered: built.candidates.length - candidates.length });
  return { events, offered: candidates, coverage, sessions: history.sessions.length, deviceSessions: history.deviceSessions, goals: goals.map((g) => ({ title: g.title, goalType: g.goalType })), profileVersion: profile.version };
}

export function buildActivityRecommendation(c: ActivityCandidate, o: ActivityOutcome, query: string) {
  const goalLine = o.goals.length ? ` Selaras dengan tujuanmu: ${o.goals.slice(0, 2).map((g) => `"${g.title}"`).join(", ")}.` : "";
  const explanation = `${c.title}: ${c.basis}${goalLine} Ini pilihan untuk kamu pertimbangkan, bukan resep olahraga.`;
  if (!explanationIsSafe(explanation)) throw new Error("EXPLANATION_REJECTED_BY_SAFETY_GATE");
  return {
    title: `Pertimbangkan: ${c.title}`,
    explanation,
    candidate: { key: c.key, name: c.title, source: "Riwayat aktivitasmu", provenance: o.sessions > 0 ? "Dihitung dari catatan aktivitasmu sendiri" : "Contoh awal (belum ada riwayat)", per100g: {}, completeness: o.coverage === "OK" ? "COMPLETE" : "PARTIAL", origin: "ACTIVITY_HISTORY" },
    activity: { type: c.type, durationMinutes: c.minutes },
    evidenceRefs: [{ kind: "USER_ACTIVITY_HISTORY", sessions: o.sessions, windowDays: 28 }],
    limitations: [
      "Durasinya tidak melebihi sesi terpanjang yang pernah kamu catat.",
      o.sessions === 0 ? "Belum ada riwayat aktivitas, jadi pilihan ini hanya contoh awal." : `Berdasarkan ${o.sessions} sesi dalam 28 hari terakhir${o.deviceSessions > 0 ? `, termasuk ${o.deviceSessions} dari perangkat` : " (semua manual; jam tangan tidak diperlukan)"}.`,
      "Ini bukan resep olahraga dan bukan saran medis. Jika ada kondisi kesehatan atau cedera, tanyakan ke tenaga kesehatan.",
      "Menyelesaikan rencana tidak menjamin aman, dan tidak berarti glukosamu membaik.",
    ],
    dataCoverage: o.coverage === "OK" ? "COMPLETE" : "PARTIAL",
    policyVersion: SAFETY_POLICY_VERSION,
    rankingReason: "Diurutkan dari yang paling mirip kebiasaanmu, tanpa menambah beban.",
    personalization: { profileVersion: o.profileVersion, rulesVersion: PERSONALIZATION_RULES_VERSION, penalty: 0, matchedTerms: [] as string[] },
    query,
    requiresConfirmation: true as const,
    strictConstraintsActive: false,
  };
}
