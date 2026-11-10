import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { conflict, forbidden, notFound, unprocessable } from "../../shared/errors/app-error.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { ACTIVITY_COUNTED_QUALITY } from "../activity/activity.model.ts";
import { consentService } from "../consent/consent.service.ts";
import type { ConsentPurpose } from "../consent/consent.policy.ts";
import { currentPolicy } from "../consent/consent.policy.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { MAX_BACKFILL_DAYS, MIN_ACTIVITY_MINUTES, MIN_COHORT, SCORING_VERSION, aliasKey, aliasProblem, desiredEvents, rank, reconcile, round4, totalScore } from "./scoring.model.ts";

const need = async (userId: string, ...purposes: ConsentPurpose[]) => {
  for (const p of purposes) await consentService.requireConsent(userId, p);
};
const has = async (userId: string, ...purposes: ConsentPurpose[]) => {
  try {
    await need(userId, ...purposes);
    return true;
  } catch {
    return false;
  }
};
const day = (d: Date) => d.toISOString().slice(0, 10);
const DAY_MS = 86_400_000;
const isUnique = (e: unknown) => e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002";

async function activeMembership(userId: string, communityId: string) {
  const m = await prisma.communityMembership.findUnique({ where: { userId_communityId: { userId, communityId } } });
  return m && m.status === "ACTIVE" ? m : null;
}

type Chal = NonNullable<Awaited<ReturnType<typeof prisma.challenge.findFirst>>>;
const periodDays = (c: Chal) => Math.round((c.endsOn.getTime() - c.startsOn.getTime()) / DAY_MS) + 1;

async function eligibleDays(userId: string, c: Chal, tz: string, today: string) {
  const from = new Date(c.startsOn.getTime() - DAY_MS);
  const to = new Date(Math.min(c.endsOn.getTime(), Date.parse(today + "T00:00:00Z")) + 2 * DAY_MS);
  const sessions = await prisma.activitySession.findMany({
    where: { userId, archivedAt: null, qualityStatus: { in: [...ACTIVITY_COUNTED_QUALITY] }, durationMinutes: { gte: MIN_ACTIVITY_MINUTES }, startedAt: { gte: from, lt: to } },
    select: { startedAt: true },
  });
  const lo = day(c.startsOn), hi = day(c.endsOn) < today ? day(c.endsOn) : today;
  const activityDays = [...new Set(sessions.map((s) => localRecordTime(s.startedAt, tz).localDate))].filter((d) => d >= lo && d <= hi);
  const checks = await prisma.challengeCheckin.findMany({ where: { challengeId: c.id, userId }, select: { localDate: true } });
  const checkinDays = checks.map((k) => day(k.localDate)).filter((d) => d >= lo && d <= hi);
  return { activityDays, checkinDays };
}

/** Menyelaraskan buku besar dengan sumber saat ini. Idempoten; koreksi/arsip sumber menghasilkan pembalikan. */
export async function syncScores(userId: string, c: Chal, tz?: string) {
  const zone = tz ?? (await preferencesService.get(userId)).timezone;
  const today = localRecordTime(new Date(), zone).localDate;
  const { activityDays, checkinDays } = await eligibleDays(userId, c, zone, today);
  const desired = desiredEvents({ targetDays: c.targetDays, periodDays: periodDays(c), activityDays, checkinDays });
  return prisma.$transaction(async (tx) => {
    const rows = await tx.scoreEvent.findMany({ where: { challengeId: c.id, userId } });
    const existing = rows.map((r) => ({ id: r.id, eventType: r.eventType, sourceKey: r.sourceKey, points: r.points.toNumber(), reversalOf: r.reversalOf }));
    const { toAdd, toReverse } = reconcile(existing, desired);
    for (const a of toAdd) {
      try {
        await tx.scoreEvent.create({ data: { challengeId: c.id, userId, eventType: a.eventType, sourceKey: a.sourceKey, localDate: a.localDate ? new Date(a.localDate + "T00:00:00Z") : null, points: a.points, scoringVersion: SCORING_VERSION, reason: a.reason } });
      } catch (e) {
        if (!isUnique(e)) throw e; // sinkronisasi bersamaan: yang lain sudah menulis
      }
    }
    for (const r of toReverse) {
      try {
        await tx.scoreEvent.create({ data: { challengeId: c.id, userId, eventType: r.eventType as "ACTIVITY_DAY", sourceKey: r.sourceKey, points: -r.points, scoringVersion: SCORING_VERSION, reason: "Dibalik: sumber dikoreksi, diarsipkan, atau tidak lagi memenuhi syarat", reversalOf: r.id } });
      } catch (e) {
        if (!isUnique(e)) throw e;
      }
    }
    const all = await tx.scoreEvent.findMany({ where: { challengeId: c.id, userId } });
    return { score: Math.min(100, Math.max(0, totalScore(all.map((e) => ({ points: e.points.toNumber() }))))), activityDays: activityDays.length, checkinDays: checkinDays.length, added: toAdd.length, reversed: toReverse.length, events: all.length };
  });
}

const publicChallenge = (c: Chal) => ({ id: c.id, communityId: c.communityId, title: c.title, description: c.description, kind: c.kind, startsOn: day(c.startsOn), endsOn: day(c.endsOn), targetDays: c.targetDays, scoringVersion: c.scoringVersion, status: c.status });

export const communityService = {
  async regions() {
    return { items: (await prisma.region.findMany({ orderBy: { name: "asc" } })).map((r) => ({ code: r.code, name: r.name, level: r.level })) };
  },

  /** Direktori wilayah: hanya nama, deskripsi, dan jumlah anggota yang dikaburkan (<5). Tidak ada daftar orang. */
  async communities(userId: string, regionCode: string) {
    const region = await prisma.region.findUnique({ where: { code: regionCode } });
    if (!region) throw notFound("REGION_NOT_FOUND", "Wilayah tidak ditemukan.");
    const list = await prisma.community.findMany({ where: { regionCode }, orderBy: { name: "asc" } });
    const mine = await prisma.communityMembership.findMany({ where: { userId, communityId: { in: list.map((c) => c.id) } } });
    const counts = await prisma.communityMembership.groupBy({ by: ["communityId"], where: { communityId: { in: list.map((c) => c.id) }, status: "ACTIVE" }, _count: true });
    return {
      region: { code: region.code, name: region.name },
      items: list.map((c) => {
        const n = counts.find((x) => x.communityId === c.id)?._count ?? 0;
        return { id: c.id, name: c.name, description: c.description, memberCount: n < MIN_COHORT ? null : n, memberCountLabel: n < MIN_COHORT ? `kurang dari ${MIN_COHORT}` : String(n), myStatus: mine.find((m) => m.communityId === c.id)?.status ?? "NONE" };
      }),
    };
  },

  async mine(userId: string) {
    const rows = await prisma.communityMembership.findMany({ where: { userId, status: "ACTIVE" }, include: { community: { include: { region: true } } }, orderBy: { joinedAt: "desc" } });
    // Tanpa persetujuan keanggotaan, keanggotaan tidak ditampilkan (penarikan berlaku segera).
    if (!(await has(userId, "community_membership"))) return { items: [], consentRequired: true };
    return { items: rows.map((m) => ({ communityId: m.communityId, name: m.community.name, region: m.community.region.name, alias: m.alias, joinedAt: m.joinedAt.toISOString() })), consentRequired: false };
  },

  async join(userId: string, communityId: string, alias: string) {
    await need(userId, "community_membership");
    const problem = aliasProblem(alias);
    if (problem) throw unprocessable("INVALID_ALIAS", problem);
    const community = await prisma.community.findUnique({ where: { id: communityId } });
    if (!community) throw notFound("COMMUNITY_NOT_FOUND", "Komunitas tidak ditemukan.");
    try {
      return await prisma.$transaction(async (tx) => {
        const existing = await tx.communityMembership.findUnique({ where: { userId_communityId: { userId, communityId } } });
        if (existing?.status === "ACTIVE") return { created: false, communityId, alias: existing.alias };
        const row = existing
          ? await tx.communityMembership.update({ where: { id: existing.id }, data: { status: "ACTIVE", alias: alias.trim(), aliasKey: aliasKey(alias), leftAt: null, joinedAt: new Date() } })
          : await tx.communityMembership.create({ data: { userId, communityId, alias: alias.trim(), aliasKey: aliasKey(alias), status: "ACTIVE" } });
        await recordAudit(tx, { userId, eventType: "community_joined", metadata: { communityId } });
        return { created: true, communityId, alias: row.alias };
      });
    } catch (e) {
      if (isUnique(e)) throw conflict("ALIAS_TAKEN", "Alias ini sudah dipakai di komunitas ini. Pilih yang lain.");
      throw e;
    }
  },

  async setAlias(userId: string, communityId: string, alias: string) {
    await need(userId, "community_membership");
    const problem = aliasProblem(alias);
    if (problem) throw unprocessable("INVALID_ALIAS", problem);
    const m = await activeMembership(userId, communityId);
    if (!m) throw forbidden("NOT_A_MEMBER", "Kamu bukan anggota komunitas ini.");
    try {
      const row = await prisma.communityMembership.update({ where: { id: m.id }, data: { alias: alias.trim(), aliasKey: aliasKey(alias) } });
      return { communityId, alias: row.alias };
    } catch (e) {
      if (isUnique(e)) throw conflict("ALIAS_TAKEN", "Alias ini sudah dipakai di komunitas ini. Pilih yang lain.");
      throw e;
    }
  },

  /** Keluar dari komunitas boleh kapan saja (tidak butuh consent). Seluruh partisipasi tantangan komunitas itu berhenti dan hilang dari papan peringkat segera. */
  async leave(userId: string, communityId: string) {
    const m = await activeMembership(userId, communityId);
    if (!m) return { left: true, alreadyLeft: true };
    await prisma.$transaction(async (tx) => {
      await tx.communityMembership.update({ where: { id: m.id }, data: { status: "LEFT", leftAt: new Date() } });
      await tx.challengeParticipant.updateMany({ where: { userId, leftAt: null, challenge: { communityId } }, data: { leftAt: new Date(), leaderboardVisible: false } });
      await recordAudit(tx, { userId, eventType: "community_left", metadata: { communityId } });
    });
    return { left: true, alreadyLeft: false };
  },

  async challenges(userId: string, communityId: string) {
    await need(userId, "community_membership");
    if (!(await activeMembership(userId, communityId))) throw forbidden("NOT_A_MEMBER", "Hanya anggota yang dapat melihat tantangan komunitas.");
    const list = await prisma.challenge.findMany({ where: { communityId }, orderBy: { startsOn: "desc" } });
    const parts = await prisma.challengeParticipant.findMany({ where: { userId, challengeId: { in: list.map((c) => c.id) } } });
    return { items: list.map((c) => ({ ...publicChallenge(c), participating: parts.some((p) => p.challengeId === c.id && !p.leftAt), leaderboardVisible: parts.find((p) => p.challengeId === c.id && !p.leftAt)?.leaderboardVisible ?? false })) };
  },

  async joinChallenge(userId: string, challengeId: string, leaderboardVisible: boolean) {
    await need(userId, "community_membership", "challenge_participation");
    if (leaderboardVisible) await need(userId, "leaderboard_visibility");
    const c = await prisma.challenge.findUnique({ where: { id: challengeId } });
    if (!c) throw notFound("CHALLENGE_NOT_FOUND", "Tantangan tidak ditemukan.");
    if (!(await activeMembership(userId, c.communityId))) throw forbidden("NOT_A_MEMBER", "Bergabunglah dengan komunitasnya dulu.");
    if (c.status !== "OPEN" || c.endsOn.getTime() < Date.parse(day(new Date()) + "T00:00:00Z")) throw conflict("CHALLENGE_CLOSED", "Tantangan ini sudah ditutup.");
    await prisma.challengeParticipant.upsert({ where: { challengeId_userId: { challengeId, userId } }, create: { challengeId, userId, leaderboardVisible }, update: { leftAt: null, leaderboardVisible } });
    await recordAudit(prisma, { userId, eventType: "challenge_joined", metadata: { challengeId } });
    return { joined: true, leaderboardVisible, progress: await syncScores(userId, c) };
  },

  async leaveChallenge(userId: string, challengeId: string) {
    await prisma.challengeParticipant.updateMany({ where: { challengeId, userId, leftAt: null }, data: { leftAt: new Date(), leaderboardVisible: false } });
    return { left: true };
  },

  /** Menyalakan butuh persetujuan; mematikan selalu boleh dan berlaku segera. */
  async setVisibility(userId: string, challengeId: string, visible: boolean) {
    if (visible) await need(userId, "leaderboard_visibility");
    const p = await prisma.challengeParticipant.findUnique({ where: { challengeId_userId: { challengeId, userId } } });
    if (!p || p.leftAt) throw conflict("NOT_PARTICIPATING", "Kamu belum ikut tantangan ini.");
    await prisma.challengeParticipant.update({ where: { id: p.id }, data: { leaderboardVisible: visible } });
    return { leaderboardVisible: visible };
  },

  async checkin(userId: string, challengeId: string, localDate?: string) {
    await need(userId, "community_membership", "challenge_participation");
    const c = await prisma.challenge.findUnique({ where: { id: challengeId } });
    if (!c) throw notFound("CHALLENGE_NOT_FOUND", "Tantangan tidak ditemukan.");
    const p = await prisma.challengeParticipant.findUnique({ where: { challengeId_userId: { challengeId, userId } } });
    if (!p || p.leftAt || !(await activeMembership(userId, c.communityId))) throw conflict("NOT_PARTICIPATING", "Kamu belum ikut tantangan ini.");
    const { timezone } = await preferencesService.get(userId);
    const today = localRecordTime(new Date(), timezone).localDate;
    const target = localDate ?? today;
    const age = Math.round((Date.parse(today + "T00:00:00Z") - Date.parse(target + "T00:00:00Z")) / DAY_MS);
    if (age < 0) throw unprocessable("CHECKIN_IN_FUTURE", "Check-in tidak boleh di masa depan.");
    if (age > MAX_BACKFILL_DAYS) throw unprocessable("CHECKIN_TOO_OLD", `Check-in hanya untuk hari ini atau ${MAX_BACKFILL_DAYS} hari terakhir.`);
    if (target < day(c.startsOn) || target > day(c.endsOn)) throw unprocessable("CHECKIN_OUTSIDE_WINDOW", "Tanggal di luar periode tantangan.");
    let created = true;
    try {
      await prisma.challengeCheckin.create({ data: { challengeId, userId, localDate: new Date(target + "T00:00:00Z") } });
    } catch (e) {
      if (!isUnique(e)) throw e;
      created = false; // idempoten
    }
    return { created, localDate: target, progress: await syncScores(userId, c, timezone) };
  },

  async progress(userId: string, challengeId: string) {
    await need(userId, "challenge_participation");
    const c = await prisma.challenge.findUnique({ where: { id: challengeId } });
    if (!c) throw notFound("CHALLENGE_NOT_FOUND", "Tantangan tidak ditemukan.");
    const p = await prisma.challengeParticipant.findUnique({ where: { challengeId_userId: { challengeId, userId } } });
    if (!p || p.leftAt) throw conflict("NOT_PARTICIPATING", "Kamu belum ikut tantangan ini.");
    const sync = await syncScores(userId, c);
    const events = await prisma.scoreEvent.findMany({ where: { challengeId, userId }, orderBy: { createdAt: "asc" } });
    return {
      challenge: publicChallenge(c),
      scoringVersion: SCORING_VERSION,
      score: sync.score,
      activityDays: sync.activityDays,
      checkinDays: sync.checkinDays,
      targetDays: c.targetDays,
      leaderboardVisible: p.leaderboardVisible,
      note: "Hari tanpa catatan bukan kegagalan: skor hanya bertambah. Tidak ada poin untuk intensitas atau nilai kesehatan.",
      ledger: events.map((e) => ({ id: e.id, type: e.eventType, points: round4(e.points.toNumber()), reason: e.reason, localDate: e.localDate ? day(e.localDate) : null, reversalOf: e.reversalOf, createdAt: e.createdAt.toISOString() })),
    };
  },

  /** Papan peringkat: hanya alias + skor + peringkat. Hanya peserta yang menyalakan visibilitas DAN masih memegang ketiga persetujuan. */
  async leaderboard(userId: string, challengeId: string, q: { limit: number; offset: number }) {
    await need(userId, "community_membership");
    const c = await prisma.challenge.findUnique({ where: { id: challengeId } });
    if (!c) throw notFound("CHALLENGE_NOT_FOUND", "Tantangan tidak ditemukan.");
    if (!(await activeMembership(userId, c.communityId))) throw forbidden("NOT_A_MEMBER", "Hanya anggota yang dapat melihat papan peringkat.");

    const candidates = await prisma.challengeParticipant.findMany({ where: { challengeId, leftAt: null, leaderboardVisible: true }, take: 300, orderBy: { joinedAt: "asc" } });
    const memberships = await prisma.communityMembership.findMany({ where: { communityId: c.communityId, status: "ACTIVE", userId: { in: candidates.map((p) => p.userId) } } });
    const consented = await prisma.consentRecord.findMany({ where: { userId: { in: candidates.map((p) => p.userId) }, withdrawnAt: null, policyVersion: currentPolicy.version, purpose: { in: ["community_membership", "challenge_participation", "leaderboard_visibility"] } }, select: { userId: true, purpose: true } });
    const okUsers = new Set(candidates.map((p) => p.userId).filter((u) => ["community_membership", "challenge_participation", "leaderboard_visibility"].every((pp) => consented.some((r) => r.userId === u && r.purpose === pp))));
    const visible = memberships.filter((m) => okUsers.has(m.userId));

    const scored: { userId: string; alias: string; score: number }[] = [];
    for (const m of visible) scored.push({ userId: m.userId, alias: m.alias, score: (await syncScores(m.userId, c)).score });
    const me = (await prisma.challengeParticipant.findUnique({ where: { challengeId_userId: { challengeId, userId } } })) ?? null;
    const myScore = me && !me.leftAt ? (await syncScores(userId, c)).score : null;

    if (scored.length < MIN_COHORT) {
      return { suppressed: true, reason: `Papan peringkat tampil setelah minimal ${MIN_COHORT} peserta yang bersedia tampil.`, minimumCohort: MIN_COHORT, visibleCount: null, me: myScore === null ? null : { score: myScore, visible: Boolean(me?.leaderboardVisible) }, items: [] as never[], nextOffset: null as number | null, scoringVersion: SCORING_VERSION };
    }
    const ranked = rank(scored);
    const page = ranked.slice(q.offset, q.offset + q.limit);
    return {
      suppressed: false,
      minimumCohort: MIN_COHORT,
      visibleCount: ranked.length,
      scoringVersion: SCORING_VERSION,
      me: myScore === null ? null : { score: myScore, visible: Boolean(me?.leaderboardVisible), rank: ranked.find((r) => r.userId === userId)?.rank ?? null },
      items: page.map((r) => ({ rank: r.rank, alias: r.alias, score: r.score, isMe: r.userId === userId })),
      nextOffset: q.offset + q.limit < ranked.length ? q.offset + q.limit : null,
    };
  },
};
