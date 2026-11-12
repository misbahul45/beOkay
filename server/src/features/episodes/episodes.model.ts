export const EPISODE_VERSION = "episode-v1";
export const SLOT_LABEL: Record<string, string> = { MORNING: "pagi", MIDDAY: "siang", AFTERNOON: "sore", EVENING: "malam" };
const ACTIVITY_LABEL: Record<string, string> = { walking: "jalan kaki", cycling: "bersepeda", running: "lari", strength: "latihan kekuatan", other: "aktivitas ringan" };

export type EpisodeAction = { kind: string; status: string; slot: string | null; activityType: string | null; daysInWeek: number; doneInWeek: number };

export function buildEpisode(actions: EpisodeAction[]) {
  const accepted = actions.filter((a) => a.status === "ACCEPTED" || a.status === "WITHDRAWN");
  const declined = actions.filter((a) => a.status === "DECLINED");
  const groups = new Map<string, { kind: string; slot: string | null; activityType: string | null; planned: number; done: number }>();
  for (const a of accepted) {
    if (a.kind === "HABIT_STEP" || a.daysInWeek === 0) continue;
    const key = `${a.kind}|${a.activityType ?? ""}|${a.slot ?? ""}`;
    const g = groups.get(key) ?? { kind: a.kind, slot: a.slot, activityType: a.activityType, planned: 0, done: 0 };
    g.planned += a.daysInWeek;
    g.done += a.doneInWeek;
    groups.set(key, g);
  }
  const declinedBySlot: Record<string, number> = {};
  for (const d of declined) if (d.slot) declinedBySlot[d.slot] = (declinedBySlot[d.slot] ?? 0) + 1;
  const avoidSlots = Object.entries(declinedBySlot).filter(([, n]) => n >= 2).map(([s]) => s);
  const lines: string[] = [];
  for (const g of [...groups.values()].sort((a, b) => b.planned - a.planned).slice(0, 3)) {
    const what = g.kind === "ACTIVITY_SESSION" ? `rencana ${ACTIVITY_LABEL[g.activityType ?? "other"] ?? "aktivitas"}${g.slot ? ` ${SLOT_LABEL[g.slot]}` : ""}` : "rencana catat makan";
    lines.push(`${g.done} dari ${g.planned} hari ${what} terlaksana.`);
  }
  for (const s of avoidSlots) lines.push(`Rencana ${SLOT_LABEL[s]} ${declinedBySlot[s]} kali kamu tolak, jadi aku tidak menawarkan ${SLOT_LABEL[s]} dulu.`);
  return { lines: lines.slice(0, 6), summary: { groups: [...groups.values()], declinedBySlot, avoidSlots, accepted: accepted.length, declined: declined.length } };
}
