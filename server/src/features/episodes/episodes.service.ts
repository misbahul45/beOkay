import { prisma } from "../../infrastructure/database/prisma.ts";
import { EPISODE_VERSION, buildEpisode, type EpisodeAction } from "./episodes.model.ts";

const DAY = 86_400_000;
const asDate = (s: string) => new Date(s + "T00:00:00Z");
const iso = (d: Date) => d.toISOString().slice(0, 10);
const addDays = (s: string, n: number) => iso(new Date(asDate(s).getTime() + n * DAY));

export const episodesService = {
  async build(userId: string, weekStart: string) {
    const weekEnd = addDays(weekStart, 6);
    const rows = await prisma.coachingAction.findMany({
      where: { userId, OR: [{ startDate: { gte: asDate(addDays(weekStart, -6)), lte: asDate(weekEnd) }, status: { in: ["ACCEPTED", "WITHDRAWN"] } }, { status: "DECLINED", decidedAt: { gte: asDate(weekStart), lt: asDate(addDays(weekEnd, 1)) } }] },
      include: { outcomes: true },
    });
    const actions: EpisodeAction[] = rows.map((a) => {
      const start = iso(a.startDate);
      const days = Array.from({ length: a.days }, (_, i) => addDays(start, i)).filter((d) => d >= weekStart && d <= weekEnd);
      const done = a.outcomes.filter((o) => days.includes(iso(o.localDate)) && (o.status === "OBSERVED" || o.status === "USER_CONFIRMED")).length;
      return { kind: a.kind, status: a.status, slot: a.slot, activityType: (a.params as { activityType?: string }).activityType ?? null, daysInWeek: a.status === "DECLINED" ? 0 : days.length, doneInWeek: done };
    });
    const ep = buildEpisode(actions);
    const row = await prisma.weeklyEpisode.upsert({
      where: { userId_weekStart: { userId, weekStart: asDate(weekStart) } },
      create: { userId, weekStart: asDate(weekStart), summary: ep.summary, lines: ep.lines, version: EPISODE_VERSION },
      update: { summary: ep.summary, lines: ep.lines, version: EPISODE_VERSION },
    });
    return { weekStart, lines: row.lines, avoidSlots: ep.summary.avoidSlots, version: EPISODE_VERSION };
  },

  async avoidSlots(userId: string, today: string): Promise<string[]> {
    const latest = await prisma.weeklyEpisode.findFirst({ where: { userId, weekStart: { gte: asDate(addDays(today, -14)) } }, orderBy: { weekStart: "desc" } });
    return ((latest?.summary as { avoidSlots?: string[] } | null)?.avoidSlots ?? []).filter((s) => ["MORNING", "MIDDAY", "AFTERNOON", "EVENING"].includes(s));
  },
};
