import { createHash, randomBytes } from "node:crypto";
import { z } from "zod";
import { env } from "../../config/env.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { AppError, notFound, unprocessable } from "../../shared/errors/app-error.ts";
import { rateWindow } from "../../shared/http/rate-window.ts";
import { consentService } from "../consent/consent.service.ts";
import { reportSummaryService, type ReportSummary } from "./report-summary.service.ts";

export const MAX_ACTIVE_LINKS = 5;
export const shareLinkSchema = z
  .object({
    periodDays: z.union([z.literal(14), z.literal(30), z.literal(90)]).default(30),
    hours: z.number().int().min(1).max(168).default(72),
    label: z.string().trim().min(1).max(60).optional(),
    confirm: z.literal(true),
  })
  .strict();
export type ShareLinkInput = z.infer<typeof shareLinkSchema>;

const hashToken = (t: string) => createHash("sha256").update(t).digest("hex");
const views = rateWindow(60_000, 30);
const baseUrl = () => env.PUBLIC_BASE_URL ?? env.BETTER_AUTH_URL.replace(/\/$/, "");

const view = (l: { id: string; periodDays: number; label: string | null; expiresAt: Date; revokedAt: Date | null; lastAccessedAt: Date | null; accessCount: number; createdAt: Date }, now: Date) => ({
  id: l.id,
  periodDays: l.periodDays,
  label: l.label,
  expiresAt: l.expiresAt.toISOString(),
  revokedAt: l.revokedAt?.toISOString() ?? null,
  active: !l.revokedAt && l.expiresAt > now,
  lastAccessedAt: l.lastAccessedAt?.toISOString() ?? null,
  accessCount: l.accessCount,
  createdAt: l.createdAt.toISOString(),
});

export const shareService = {
  async create(userId: string, input: ShareLinkInput, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    await consentService.requireConsent(userId, "descriptive_summaries");
    const active = await prisma.shareLink.count({ where: { userId, revokedAt: null, expiresAt: { gt: now } } });
    if (active >= MAX_ACTIVE_LINKS) throw unprocessable("SHARE_LINK_LIMIT", `Maksimal ${MAX_ACTIVE_LINKS} tautan aktif. Cabut salah satu dulu.`);
    const token = randomBytes(32).toString("base64url");
    const row = await prisma.$transaction(async (tx) => {
      const saved = await tx.shareLink.create({ data: { userId, tokenHash: hashToken(token), periodDays: input.periodDays, label: input.label ?? null, createdAt: now, expiresAt: new Date(now.getTime() + input.hours * 3_600_000) } });
      await recordAudit(tx, { userId, eventType: "share_link_created", metadata: { linkId: saved.id, periodDays: saved.periodDays, hours: input.hours } });
      return saved;
    });
    return { ...view(row, now), url: `${baseUrl()}/s/${token}`, notice: "Siapa pun yang memegang tautan ini bisa melihat ringkasanmu sampai kedaluwarsa atau kamu cabut." };
  },

  async list(userId: string, now = new Date()) {
    const rows = await prisma.shareLink.findMany({ where: { userId }, orderBy: { createdAt: "desc" }, take: 20 });
    return { items: rows.map((r) => view(r, now)), maxActive: MAX_ACTIVE_LINKS };
  },

  async revoke(userId: string, id: string, now = new Date()) {
    const row = await prisma.shareLink.findFirst({ where: { id, userId } });
    if (!row) throw notFound("SHARE_LINK_NOT_FOUND", "Tautan tidak ditemukan.");
    if (!row.revokedAt) {
      await prisma.$transaction(async (tx) => {
        await tx.shareLink.update({ where: { id }, data: { revokedAt: now } });
        await recordAudit(tx, { userId, eventType: "share_link_revoked", metadata: { linkId: id } });
      });
    }
    return view((await prisma.shareLink.findUniqueOrThrow({ where: { id } })), now);
  },

  async resolve(token: string, client: string, now = new Date()): Promise<{ status: number; summary?: ReportSummary; expiresAt?: Date }> {
    if (views.full(client, now.getTime())) throw new AppError(429, "RATE_LIMITED", "Terlalu sering.");
    views.record(client, now.getTime());
    if (!/^[A-Za-z0-9_-]{43}$/.test(token)) return { status: 404 };
    const row = await prisma.shareLink.findUnique({ where: { tokenHash: hashToken(token) } });
    if (!row) return { status: 404 };
    if (row.revokedAt || row.expiresAt <= now) return { status: 410 };
    let summary: ReportSummary;
    try {
      summary = await reportSummaryService.build(row.userId, row.periodDays as 14 | 30 | 90, now);
    } catch (e) {
      if (e instanceof AppError && e.code === "CONSENT_REQUIRED") return { status: 410 };
      throw e;
    }
    await prisma.$transaction(async (tx) => {
      await tx.shareLink.update({ where: { id: row.id }, data: { accessCount: { increment: 1 }, lastAccessedAt: now } });
      await recordAudit(tx, { userId: row.userId, eventType: "share_link_viewed", metadata: { linkId: row.id } });
    });
    return { status: 200, summary, expiresAt: row.expiresAt };
  },
};
