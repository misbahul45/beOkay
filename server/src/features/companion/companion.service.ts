import { createHash, randomBytes } from "node:crypto";
import { z } from "zod";
import { env } from "../../config/env.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { AppError, notFound, unprocessable } from "../../shared/errors/app-error.ts";
import { rateWindow } from "../../shared/http/rate-window.ts";
import { consentService } from "../consent/consent.service.ts";
import { companionSummary, type CompanionSummary } from "./companion.summary.ts";

export const MAX_COMPANIONS = 3;
export const companionSchema = z
  .object({
    label: z.string().trim().min(1).max(40),
    days: z.union([z.literal(30), z.literal(90), z.literal(180)]).default(90),
    confirm: z.literal(true),
  })
  .strict();
export type CompanionInput = z.infer<typeof companionSchema>;

const hashToken = (t: string) => createHash("sha256").update(t).digest("hex");
const views = rateWindow(60_000, 30);
const baseUrl = () => env.PUBLIC_BASE_URL ?? env.BETTER_AUTH_URL.replace(/\/$/, "");

type Row = NonNullable<Awaited<ReturnType<typeof prisma.companionLink.findFirst>>>;
const view = (l: Row, now: Date) => ({
  id: l.id,
  label: l.label,
  expiresAt: l.expiresAt.toISOString(),
  revokedAt: l.revokedAt?.toISOString() ?? null,
  active: !l.revokedAt && l.expiresAt > now,
  lastViewedAt: l.lastViewedAt?.toISOString() ?? null,
  viewCount: l.viewCount,
  createdAt: l.createdAt.toISOString(),
});

async function hasConsent(userId: string) {
  try {
    await consentService.requireConsent(userId, "health_data_processing");
    await consentService.requireConsent(userId, "companion_sharing");
    return true;
  } catch (e) {
    if (e instanceof AppError && e.code === "CONSENT_REQUIRED") return false;
    throw e;
  }
}

export const companionService = {
  async create(userId: string, input: CompanionInput, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    await consentService.requireConsent(userId, "companion_sharing");
    const active = await prisma.companionLink.count({ where: { userId, revokedAt: null, expiresAt: { gt: now } } });
    if (active >= MAX_COMPANIONS) throw unprocessable("COMPANION_LIMIT", `Maksimal ${MAX_COMPANIONS} pendamping aktif. Cabut salah satu dulu.`);
    const token = randomBytes(32).toString("base64url");
    const row = await prisma.$transaction(async (tx) => {
      const saved = await tx.companionLink.create({ data: { userId, label: input.label, tokenHash: hashToken(token), createdAt: now, expiresAt: new Date(now.getTime() + input.days * 86_400_000) } });
      await recordAudit(tx, { userId, eventType: "companion_link_created", metadata: { linkId: saved.id, days: input.days } });
      return saved;
    });
    return { ...view(row, now), url: `${baseUrl()}/c/${token}`, notice: "Siapa pun yang memegang tautan ini bisa melihat ringkasan mingguanmu sampai kedaluwarsa atau kamu cabut. Catatan mentah tidak ditampilkan." };
  },

  async list(userId: string, now = new Date()) {
    const rows = await prisma.companionLink.findMany({ where: { userId }, orderBy: { createdAt: "desc" }, take: 20 });
    return { items: rows.map((r) => view(r, now)), maxActive: MAX_COMPANIONS };
  },

  async revoke(userId: string, id: string, now = new Date()) {
    const row = await prisma.companionLink.findFirst({ where: { id, userId } });
    if (!row) throw notFound("COMPANION_NOT_FOUND", "Pendamping tidak ditemukan.");
    if (!row.revokedAt) {
      await prisma.$transaction(async (tx) => {
        await tx.companionLink.update({ where: { id }, data: { revokedAt: now } });
        await recordAudit(tx, { userId, eventType: "companion_link_revoked", metadata: { linkId: id } });
      });
    }
    return view(await prisma.companionLink.findUniqueOrThrow({ where: { id } }), now);
  },

  async resolve(token: string, client: string, now = new Date()): Promise<{ status: number; summary?: CompanionSummary }> {
    if (views.full(client, now.getTime())) throw new AppError(429, "RATE_LIMITED", "Terlalu sering.");
    views.record(client, now.getTime());
    if (!/^[A-Za-z0-9_-]{43}$/.test(token)) return { status: 404 };
    const row = await prisma.companionLink.findUnique({ where: { tokenHash: hashToken(token) } });
    if (!row) return { status: 404 };
    if (row.revokedAt || row.expiresAt <= now) return { status: 410 };
    if (!(await hasConsent(row.userId))) {
      await prisma.$transaction(async (tx) => {
        await tx.companionLink.updateMany({ where: { userId: row.userId, revokedAt: null }, data: { revokedAt: now } });
        await recordAudit(tx, { userId: row.userId, eventType: "companion_links_revoked_consent", metadata: { linkId: row.id } });
      });
      return { status: 410 };
    }
    const summary = await companionSummary(row.userId, now);
    await prisma.$transaction(async (tx) => {
      await tx.companionLink.update({ where: { id: row.id }, data: { viewCount: { increment: 1 }, lastViewedAt: now } });
      await recordAudit(tx, { userId: row.userId, eventType: "companion_link_viewed", metadata: { linkId: row.id } });
    });
    return { status: 200, summary };
  },
};
