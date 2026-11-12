import { z } from "zod";
import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { realtime } from "../../infrastructure/realtime/realtime.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { AppError, forbidden, notFound, unprocessable } from "../../shared/errors/app-error.ts";
import { rateWindow } from "../../shared/http/rate-window.ts";
import { consentService } from "../consent/consent.service.ts";
import { notificationService } from "../notifications/notification.service.ts";
import { aliasKey } from "./scoring.model.ts";

export const AUTO_HIDE_REPORTS = 3;
export const REPORT_REASONS = ["ABUSIVE", "IMPERSONATION", "SPAM", "OTHER"] as const;
export const reportSchema = z.object({ alias: z.string().trim().min(3).max(20), reason: z.enum(REPORT_REASONS) }).strict();

const actions = rateWindow(10 * 60_000, 30);
const reports = rateWindow(24 * 60 * 60_000, 10);

export function throttleCommunity(userId: string, now = Date.now()) {
  if (actions.full(userId, now)) throw new AppError(429, "COMMUNITY_RATE_LIMITED", "Terlalu banyak aksi komunitas. Coba lagi beberapa menit lagi.");
  actions.record(userId, now);
}

const isUnique = (e: unknown) => e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002";

async function hide(membershipId: string, now: Date) {
  const m = await prisma.communityMembership.findUniqueOrThrow({ where: { id: membershipId } });
  if (m.hiddenAt) return false;
  await prisma.$transaction(async (tx) => {
    await tx.communityMembership.update({ where: { id: m.id }, data: { hiddenAt: now } });
    await recordAudit(tx, { userId: m.userId, eventType: "community_alias_hidden", metadata: { communityId: m.communityId, membershipId: m.id } });
  });
  await notificationService.notify(m.userId, { kind: "COMMUNITY", title: "Aliasmu disembunyikan sementara", body: "Beberapa anggota melaporkan aliasmu. Alias tidak tampil di papan peringkat sampai ditinjau. Mengganti alias membuatnya tampil lagi.", action: "OPEN_COMMUNITY", refId: m.communityId, dedupeKey: `alias-hidden:${m.id}:${m.aliasKey}` });
  const open = await prisma.challenge.findMany({ where: { communityId: m.communityId, status: "OPEN" }, select: { id: true } });
  for (const c of open) realtime.toTopic(`challenge:${c.id}`, { type: "leaderboard.changed", challengeId: c.id });
  return true;
}

export const moderationService = {
  async report(userId: string, challengeId: string, input: z.infer<typeof reportSchema>, now = new Date()) {
    await consentService.requireConsent(userId, "community_membership");
    if (reports.full(userId, now.getTime())) throw new AppError(429, "REPORT_RATE_LIMITED", "Batas laporan hari ini sudah tercapai.");
    const c = await prisma.challenge.findUnique({ where: { id: challengeId }, select: { communityId: true } });
    if (!c) throw notFound("CHALLENGE_NOT_FOUND", "Tantangan tidak ditemukan.");
    const mine = await prisma.communityMembership.findUnique({ where: { userId_communityId: { userId, communityId: c.communityId } } });
    if (!mine || mine.status !== "ACTIVE") throw forbidden("NOT_A_MEMBER", "Hanya anggota yang dapat melapor.");
    const key = aliasKey(input.alias);
    const target = await prisma.communityMembership.findFirst({ where: { communityId: c.communityId, aliasKey: key, status: "ACTIVE" } });
    if (!target) throw notFound("ALIAS_NOT_FOUND", "Alias tidak ditemukan di komunitas ini.");
    if (target.userId === userId) throw unprocessable("CANNOT_REPORT_SELF", "Kamu tidak bisa melaporkan aliasmu sendiri.");
    reports.record(userId, now.getTime());
    try {
      await prisma.$transaction(async (tx) => {
        await tx.communityReport.create({ data: { userId, membershipId: target.id, communityId: c.communityId, aliasKey: key, aliasSnapshot: target.alias, reason: input.reason, status: "OPEN", createdAt: now } });
        await recordAudit(tx, { userId, eventType: "community_report_created", metadata: { communityId: c.communityId, reason: input.reason } });
      });
    } catch (e) {
      if (!isUnique(e)) throw e;
      return { reported: true, duplicate: true, message: "Kamu sudah melaporkan alias ini. Terima kasih." };
    }
    const reporters = await prisma.communityReport.count({ where: { membershipId: target.id, aliasKey: key, status: "OPEN" } });
    if (reporters >= AUTO_HIDE_REPORTS) await hide(target.id, now);
    return { reported: true, duplicate: false, message: "Terima kasih. Laporan akan ditinjau pemilik layanan." };
  },

  async onAliasChanged(membershipId: string, now = new Date()) {
    const m = await prisma.communityMembership.findUniqueOrThrow({ where: { id: membershipId } });
    await prisma.$transaction(async (tx) => {
      const closed = await tx.communityReport.updateMany({ where: { membershipId, status: "OPEN" }, data: { status: "ALIAS_CHANGED", resolvedAt: now } });
      if (m.hiddenAt) await tx.communityMembership.update({ where: { id: membershipId }, data: { hiddenAt: null } });
      if (closed.count || m.hiddenAt) await recordAudit(tx, { userId: m.userId, eventType: "community_alias_changed_after_report", metadata: { membershipId, closedReports: closed.count } });
    });
  },

  async queue() {
    const open = await prisma.communityReport.groupBy({ by: ["membershipId", "aliasSnapshot"], where: { status: "OPEN" }, _count: { _all: true }, _min: { createdAt: true } });
    const ms = await prisma.communityMembership.findMany({ where: { id: { in: open.map((o) => o.membershipId) } }, include: { community: { select: { name: true } } } });
    const reasons = await prisma.communityReport.groupBy({ by: ["membershipId", "reason"], where: { status: "OPEN" }, _count: { _all: true } });
    return open
      .map((o) => {
        const m = ms.find((x) => x.id === o.membershipId);
        return { membershipId: o.membershipId, alias: o.aliasSnapshot, community: m?.community.name ?? null, reports: o._count._all, hidden: Boolean(m?.hiddenAt), firstReportedAt: o._min.createdAt?.toISOString() ?? null, reasons: Object.fromEntries(reasons.filter((r) => r.membershipId === o.membershipId).map((r) => [r.reason, r._count._all])) };
      })
      .sort((a, b) => b.reports - a.reports);
  },

  async resolve(membershipId: string, action: "uphold" | "dismiss", note: string | null, now = new Date()) {
    const m = await prisma.communityMembership.findUnique({ where: { id: membershipId } });
    if (!m) throw notFound("MEMBERSHIP_NOT_FOUND", "Keanggotaan tidak ditemukan.");
    if (action === "uphold") await hide(membershipId, now);
    await prisma.$transaction(async (tx) => {
      const n = await tx.communityReport.updateMany({ where: { membershipId, status: "OPEN" }, data: { status: action === "uphold" ? "UPHELD" : "DISMISSED", resolvedAt: now, resolutionNote: note } });
      if (action === "dismiss" && m.hiddenAt) await tx.communityMembership.update({ where: { id: membershipId }, data: { hiddenAt: null } });
      await recordAudit(tx, { userId: m.userId, eventType: action === "uphold" ? "community_reports_upheld" : "community_reports_dismissed", metadata: { membershipId, reports: n.count } });
    });
    if (action === "uphold") await notificationService.notify(m.userId, { kind: "COMMUNITY", title: "Ganti alias untuk tampil lagi", body: "Setelah ditinjau, aliasmu tetap disembunyikan dari papan peringkat. Ganti alias di Komunitas agar tampil kembali.", action: "OPEN_COMMUNITY", refId: m.communityId, dedupeKey: `alias-upheld:${m.id}:${m.aliasKey}` });
    return { membershipId, action };
  },
};
