import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { consentService } from "../consent/consent.service.ts";
import { notificationService } from "../notifications/notification.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { RECOGNITION_RULES, RECOGNITION_RULES_VERSION, earned, longestStreak, weekStreak, type RecognitionFacts } from "./recognition.model.ts";

const isUnique = (e: unknown) => e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002";
const iso = (d: Date) => d.toISOString().slice(0, 10);

async function facts(userId: string): Promise<RecognitionFacts> {
  const [joined, completed, finished, checkins, plansDone] = await Promise.all([
    prisma.challengeParticipant.count({ where: { userId } }),
    prisma.challengeParticipant.count({ where: { userId, completionStatus: "COMPLETED" } }),
    prisma.challengeParticipant.count({ where: { userId, completionStatus: { in: ["COMPLETED", "PARTICIPATED"] } } }),
    prisma.weeklyCheckin.findMany({ where: { userId }, select: { weekStart: true } }),
    prisma.coachingOutcome.count({ where: { userId, status: { in: ["OBSERVED", "USER_CONFIRMED"] } } }),
  ]);
  let loggingStreak: number | null = null;
  try {
    await consentService.requireConsent(userId, "health_data_processing");
    const tz = (await preferencesService.get(userId)).timezone;
    const since = new Date(Date.now() - 60 * 86_400_000);
    const [meals, sessions, glucose] = await Promise.all([
      prisma.mealLog.findMany({ where: { userId, archivedAt: null, consumedAt: { gte: since } }, select: { consumedAt: true } }),
      prisma.activitySession.findMany({ where: { userId, archivedAt: null, startedAt: { gte: since } }, select: { startedAt: true } }),
      prisma.glucoseObservation.findMany({ where: { userId, archivedAt: null, measuredAt: { gte: since } }, select: { measuredAt: true } }),
    ]);
    const day = (d: Date) => localRecordTime(d, tz).localDate;
    loggingStreak = longestStreak([...meals.map((m) => day(m.consumedAt)), ...sessions.map((s) => day(s.startedAt)), ...glucose.map((g) => day(g.measuredAt))]);
  } catch {
    loggingStreak = null;
  }
  return { challengesJoined: joined, challengesCompleted: completed, challengesFinished: finished, reflections: checkins.length, reflectionStreak: weekStreak(checkins.map((c) => iso(c.weekStart))), plansDone, loggingStreak };
}

export const recognitionService = {
  async refresh(userId: string) {
    const f = await facts(userId);
    const have = new Set((await prisma.recognition.findMany({ where: { userId }, select: { key: true } })).map((r) => r.key));
    const fresh = [];
    for (const rule of earned(f)) {
      if (have.has(rule.key)) continue;
      try {
        const row = await prisma.recognition.create({ data: { userId, key: rule.key, category: rule.category, title: rule.title, detail: rule.detail } });
        fresh.push(row);
        await notificationService.notify(userId, { kind: "RECOGNITION", title: `Pencapaian baru: ${rule.title}`, body: rule.detail, action: "OPEN_RECOGNITIONS", refId: row.id, dedupeKey: `recognition:${rule.key}` });
      } catch (e) {
        if (!isUnique(e)) throw e;
      }
    }
    return { facts: f, created: fresh.length };
  },

  async list(userId: string) {
    await this.refresh(userId);
    const rows = await prisma.recognition.findMany({ where: { userId }, orderBy: { achievedAt: "desc" } });
    const got = new Set(rows.map((r) => r.key));
    return {
      rulesVersion: RECOGNITION_RULES_VERSION,
      items: rows.map((r) => ({ key: r.key, category: r.category, title: r.title, detail: r.detail, achievedAt: r.achievedAt.toISOString() })),
      upcoming: RECOGNITION_RULES.filter((r) => !got.has(r.key)).map((r) => ({ key: r.key, category: r.category, title: r.title, detail: r.detail })),
      note: "Pencapaian bersifat pribadi dan hanya menghargai usaha, bukan nilai kesehatan.",
    };
  },
};
