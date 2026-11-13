import { prisma } from "../../src/infrastructure/database/prisma.ts";

const days = Number(process.argv[2] ?? 28);
const since = new Date(Date.now() - days * 86_400_000);
const ratio = (a: number, b: number) => (b ? Math.round((a / b) * 1000) / 1000 : null);

const [users, active, recOffered, recAccepted, outcomes, coachProposed, coachAccepted, coachObserved, interventions, delivered, useful, notUseful, withheld, safety, memProposed, memConfirmed, memDismissed, journeys, deviceUsers] = await Promise.all([
  prisma.users.count(),
  prisma.dailyBehaviorFact.findMany({ where: { localDate: { gte: since }, OR: [{ sessionCount: { gt: 0 } }, { mealsLogged: { gt: 0 } }] }, distinct: ["userId"], select: { userId: true } }),
  prisma.recommendation.count({ where: { createdAt: { gte: since } } }),
  prisma.recommendation.count({ where: { createdAt: { gte: since }, status: "ACCEPTED" } }),
  prisma.recommendationOutcome.count({ where: { observedAt: { gte: since } } }),
  prisma.coachingAction.count({ where: { createdAt: { gte: since } } }),
  prisma.coachingAction.count({ where: { createdAt: { gte: since }, status: { in: ["ACCEPTED", "COMPLETED"] } } }),
  prisma.coachingOutcome.count({ where: { createdAt: { gte: since }, status: "OBSERVED" } }),
  prisma.interventionDecision.count({ where: { decidedAt: { gte: since } } }),
  prisma.interventionDecision.count({ where: { decidedAt: { gte: since }, deliveryStatus: { in: ["DELIVERED", "OPENED", "RESPONDED"] } } }),
  prisma.interventionDecision.count({ where: { decidedAt: { gte: since }, response: "USEFUL" } }),
  prisma.interventionDecision.count({ where: { decidedAt: { gte: since }, response: "NOT_USEFUL" } }),
  prisma.interventionDecision.count({ where: { decidedAt: { gte: since }, reason: { startsWith: "WITHHOLD:" } } }),
  prisma.conversationMessage.count({ where: { createdAt: { gte: since }, role: "ASSISTANT", route: "SAFETY" } }),
  prisma.memoryItem.count({ where: { createdAt: { gte: since } } }),
  prisma.memoryItem.count({ where: { createdAt: { gte: since }, status: "ACTIVE" } }),
  prisma.memoryItem.count({ where: { createdAt: { gte: since }, status: "DISMISSED" } }),
  prisma.healthProfile.groupBy({ by: ["journey"], _count: { _all: true } }),
  prisma.dailySteps.findMany({ where: { syncedAt: { gte: since } }, distinct: ["userId"], select: { userId: true } }),
]);

console.log(JSON.stringify({
  windowDays: days,
  users,
  journeys: Object.fromEntries(journeys.map((j) => [j.journey, j._count._all])),
  engagement: { usersWithRecords: active.length, usersWithDeviceData: deviceUsers.length },
  recommendations: { offered: recOffered, accepted: recAccepted, acceptanceRate: ratio(recAccepted, recOffered), measuredOutcomes: outcomes, measuredPerAccepted: ratio(outcomes, recAccepted) },
  coaching: { proposed: coachProposed, accepted: coachAccepted, observedDays: coachObserved },
  interventions: { decisions: interventions, delivered, useful, notUseful, usefulRate: ratio(useful, useful + notUseful), withheld },
  safety: { safetyReplies: safety },
  memory: { proposed: memProposed, confirmed: memConfirmed, dismissed: memDismissed, confirmRate: ratio(memConfirmed, memProposed) },
  note: "Dihitung dari tabel domain apa adanya. Tanpa pengguna nyata, keluaran hanya membuktikan perhitungannya berjalan, bukan dampak.",
}, null, 2));
process.exit(0);
