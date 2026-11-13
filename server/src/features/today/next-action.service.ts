import { prisma } from "../../infrastructure/database/prisma.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { cohortService } from "../cohort/cohort.service.ts";
import { consentService } from "../consent/consent.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { dailyFacts } from "../projections/daily-facts.service.ts";
import { checkinsService } from "../checkins/checkins.service.ts";
import { baselineActiveDaysPerWeek, bandOf, peerComparison, personalBest, returnAfterBreak, SCORING_V2_VERSION, weekScore } from "../community/scoring.v2.ts";

export const NEXT_ACTION_VERSION = "next-action-v1";
export const FLOW = ["TODAY", "NEXT_ACTION", "CONFIRM", "PROGRESS", "REFLECTION", "INSIGHTS", "CHALLENGES"] as const;
export type SparkState = "NEUTRAL" | "THINKING" | "ENCOURAGING" | "CELEBRATING" | "AWAITING_CONFIRMATION" | "SAFETY_WARNING";

type Kind = "SAFETY_FOLLOW_UP" | "CONFIRM_RECOMMENDATION" | "CONFIRM_PLAN" | "DO_PLANNED_ACTION" | "CONFIRM_MEMORY" | "WEEKLY_REFLECTION" | "CELEBRATE_RETURN" | "LOG_SOMETHING";
export type NextAction = { kind: Kind; step: (typeof FLOW)[number]; spark: SparkState; title: string; body: string; target: string; ref: string | null; source: string };

const addDays = (d: string, n: number) => new Date(Date.parse(d + "T00:00:00Z") + n * 86_400_000).toISOString().slice(0, 10);

export const nextActionService = {
  async get(userId: string, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    const [{ timezone }, journey, personal] = await Promise.all([preferencesService.get(userId), cohortService.resolve(userId), consentService.hasConsent(userId, "personalized_ai")]);
    const today = localRecordTime(now, timezone).localDate;
    const facts = await dailyFacts.list(userId, addDays(today, -27), today, timezone);
    const back = returnAfterBreak(facts, today);
    const pick = async (): Promise<NextAction> => {
      const safety = await prisma.conversationMessage.findFirst({ where: { userId, role: "ASSISTANT", route: "SAFETY", createdAt: { gte: new Date(now.getTime() - 12 * 3_600_000) } }, orderBy: { createdAt: "desc" }, select: { id: true } });
      if (safety) return { kind: "SAFETY_FOLLOW_UP", step: "TODAY", spark: "SAFETY_WARNING", title: "Utamakan keselamatanmu", body: "Tadi ada keluhan yang perlu ditangani tenaga kesehatan. Saran kebiasaan ditunda dulu.", target: "COACH", ref: safety.id, source: "conversation_safety" };
      if (!journey.capabilities.coaching) return { kind: "LOG_SOMETHING", step: "TODAY", spark: "NEUTRAL", title: "Catat harimu", body: "Kamu tetap bisa mencatat makan, aktivitas, dan tidurmu.", target: "LOG", ref: null, source: "journey_logging_only" };
      if (personal) {
        const rec = await prisma.recommendation.findFirst({ where: { userId, status: "OFFERED", expiresAt: { gt: now } }, orderBy: { createdAt: "desc" }, select: { id: true, recType: true } });
        if (rec) return { kind: "CONFIRM_RECOMMENDATION", step: "CONFIRM", spark: "AWAITING_CONFIRMATION", title: "Ada pilihan menunggu persetujuanmu", body: "Tidak ada yang disimpan sebelum kamu memilih.", target: "COACH", ref: rec.id, source: "agent_recommendation" };
        const proposed = await prisma.coachingAction.findFirst({ where: { userId, status: "PROPOSED", expiresAt: { gt: now } }, orderBy: { createdAt: "desc" }, select: { id: true, title: true } });
        if (proposed) return { kind: "CONFIRM_PLAN", step: "CONFIRM", spark: "AWAITING_CONFIRMATION", title: proposed.title, body: "Rencana kecil ini baru berlaku setelah kamu menerimanya.", target: "COACHING", ref: proposed.id, source: "coaching_proposal" };
      }
      if (back.returned) return { kind: "CELEBRATE_RETURN", step: "PROGRESS", spark: "CELEBRATING", title: "Selamat datang kembali", body: `Hari ini kamu bergerak lagi setelah ${back.gapDays} hari. Itu yang terpenting.`, target: "INSIGHTS", ref: null, source: "projection" };
      const accepted = await prisma.coachingAction.findFirst({ where: { userId, status: "ACCEPTED", startDate: { lte: new Date(today + "T00:00:00Z") } }, orderBy: { startDate: "desc" }, select: { id: true, title: true } });
      if (accepted) return { kind: "DO_PLANNED_ACTION", step: "NEXT_ACTION", spark: "ENCOURAGING", title: accepted.title, body: "Cukup langkah kecil. Hari tanpa catatan bukan kegagalan.", target: "COACHING", ref: accepted.id, source: "coaching_action" };
      if (personal) {
        const mem = await prisma.memoryItem.findFirst({ where: { userId, status: "PROPOSED" }, orderBy: { createdAt: "desc" }, select: { id: true, content: true } });
        if (mem) return { kind: "CONFIRM_MEMORY", step: "CONFIRM", spark: "AWAITING_CONFIRMATION", title: "Boleh aku ingat ini?", body: mem.content, target: "MEMORY", ref: mem.id, source: "memory_proposal" };
      }
      const dow = new Date(today + "T00:00:00Z").getUTCDay();
      if (dow === 0 || dow === 6) return { kind: "WEEKLY_REFLECTION", step: "REFLECTION", spark: "NEUTRAL", title: "Refleksi mingguan", body: "Lihat yang sudah berjalan minggu ini. Sekitar 2 menit.", target: "REFLECTION", ref: null, source: "calendar" };
      return { kind: "LOG_SOMETHING", step: "TODAY", spark: "ENCOURAGING", title: "Satu catatan kecil", body: "Catat satu makan atau aktivitas hari ini.", target: "LOG", ref: null, source: "default" };
    };
    const action = await pick();
    const week = facts.slice(-7);
    const prior = facts.slice(0, -7);
    return { version: NEXT_ACTION_VERSION, flow: FLOW, journey: journey.journey, today, action, energy: await checkinsService.energyToday(userId, now), progress: { scoreVersion: SCORING_V2_VERSION, week: weekScore(week, baselineActiveDaysPerWeek(prior)), personalBest: personalBest(facts), returnAfterBreak: back } };
  },

  async peers(userId: string, now = new Date()) {
    await consentService.requireConsent(userId, "challenge_participation");
    const { timezone } = await preferencesService.get(userId);
    const today = localRecordTime(now, timezone).localDate;
    const mine = await dailyFacts.list(userId, addDays(today, -27), today, timezone);
    const myBand = bandOf(baselineActiveDaysPerWeek(mine));
    const communities = await prisma.communityMembership.findMany({ where: { userId, status: "ACTIVE" }, select: { communityId: true } });
    const others = await prisma.communityMembership.findMany({ where: { communityId: { in: communities.map((c) => c.communityId) }, status: "ACTIVE", userId: { not: userId } }, select: { userId: true }, distinct: ["userId"], take: 200 });
    const peerScores: number[] = [];
    for (const o of others) {
      if (!(await consentService.hasConsent(o.userId, "challenge_participation"))) continue;
      const f = await dailyFacts.list(o.userId, addDays(today, -27), today);
      if (bandOf(baselineActiveDaysPerWeek(f)) !== myBand) continue;
      peerScores.push(weekScore(f.slice(-7), null).activeDays);
    }
    const cmp = peerComparison(weekScore(mine.slice(-7), null).activeDays, peerScores);
    return { version: SCORING_V2_VERSION, band: myBand, ...cmp, note: cmp.comparable ? "Dibandingkan dengan kelompok sepadan berdasarkan kebiasaan dasar, tanpa nama dan tanpa nilai kesehatan." : "Kelompok sepadan belum cukup besar, jadi tidak ada perbandingan." };
  },
};
