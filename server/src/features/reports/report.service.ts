import { z } from "zod";
import { env } from "../../config/env.ts";
import { smtpEmailSender } from "../../infrastructure/email/smtp-email-sender.ts";
import type { EmailSender } from "../../infrastructure/email/email-sender.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { AppError } from "../../shared/errors/app-error.ts";
import { logEvent } from "../../shared/http/logger.ts";
import { rateWindow } from "../../shared/http/rate-window.ts";

export const REPORT_CATEGORIES = ["bug", "adverse_event", "privacy", "other"] as const;
export const CATEGORY_LABEL: Record<(typeof REPORT_CATEGORIES)[number], string> = {
  bug: "Masalah aplikasi",
  adverse_event: "Kejadian tidak diinginkan",
  privacy: "Privasi atau data",
  other: "Lainnya",
};

export const reportSchema = z
  .object({
    category: z.enum(REPORT_CATEGORIES),
    message: z.string().trim().min(5).max(2000).regex(/^[^\x00-\x08\x0B\x0C\x0E-\x1F\x7F]*$/),
    contactOk: z.boolean().default(false),
    appVersion: z.string().regex(/^[0-9A-Za-z.+_-]{1,40}$/).optional(),
  })
  .strict();
export type ReportInput = z.infer<typeof reportSchema>;

const limiter = rateWindow(60 * 60_000, 5);
let sender: EmailSender = smtpEmailSender;
export const setReportSender = (s: EmailSender) => {
  sender = s;
};

const escapeHtml = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

export const reportService = {
  async submit(userId: string, email: string, input: ReportInput, now = Date.now()) {
    if (limiter.full(userId, now)) throw new AppError(429, "REPORT_RATE_LIMITED", "Terlalu banyak laporan dalam satu jam. Coba lagi nanti.");
    limiter.record(userId, now);
    const row = await prisma.$transaction(async (tx) => {
      const saved = await tx.incidentReport.create({ data: { userId, category: input.category, message: input.message, contactOk: input.contactOk, appVersion: input.appVersion ?? null } });
      await recordAudit(tx, { userId, eventType: "incident_reported", metadata: { reportId: saved.id, category: saved.category } });
      return saved;
    });
    let emailed = false;
    if (env.INCIDENT_EMAIL_TO) {
      const contact = input.contactOk ? email : "(pengguna tidak meminta dihubungi)";
      const label = CATEGORY_LABEL[input.category];
      const lines = [`Kategori: ${label}`, `ID laporan: ${row.id}`, `Waktu: ${row.createdAt.toISOString()}`, `Versi aplikasi: ${row.appVersion ?? "-"}`, `Kontak: ${contact}`, "", input.message];
      try {
        await sender.send({
          to: env.INCIDENT_EMAIL_TO,
          subject: `[beOkay] ${input.category === "adverse_event" ? "KEJADIAN" : "Laporan"}: ${label}`,
          text: lines.join("\n"),
          html: `<pre style="font-family:system-ui;white-space:pre-wrap">${escapeHtml(lines.join("\n"))}</pre>`,
        });
        await prisma.incidentReport.update({ where: { id: row.id }, data: { emailedAt: new Date() } });
        emailed = true;
      } catch {
        logEvent("error", "incident_email_failed", { reportId: row.id });
      }
    } else {
      logEvent("warn", "incident_email_not_configured", { reportId: row.id, category: row.category });
    }
    return {
      id: row.id,
      category: row.category,
      emailed,
      createdAt: row.createdAt.toISOString(),
      message: input.category === "adverse_event" ? "Terima kasih. Laporanmu tersimpan. Bila kamu merasa tidak sehat sekarang, hubungi tenaga kesehatan atau layanan darurat 119." : "Terima kasih. Laporanmu tersimpan dan akan ditinjau.",
    };
  },

  async mine(userId: string) {
    const rows = await prisma.incidentReport.findMany({ where: { userId }, orderBy: { createdAt: "desc" }, take: 20, select: { id: true, category: true, createdAt: true, emailedAt: true } });
    return { items: rows.map((r) => ({ id: r.id, category: r.category, createdAt: r.createdAt.toISOString(), forwarded: r.emailedAt !== null })) };
  },
};
