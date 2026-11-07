import nodemailer from "nodemailer";
import { env } from "../../config/env.ts";
import type { EmailMessage, EmailSender } from "./email-sender.ts";

const transport = nodemailer.createTransport({
  host: env.SMTP_HOST,
  port: env.SMTP_PORT,
  secure: env.SMTP_SECURE,
  auth: env.SMTP_USER && env.SMTP_PASS ? { user: env.SMTP_USER, pass: env.SMTP_PASS } : undefined,
});

export const smtpEmailSender: EmailSender = {
  async send(message: EmailMessage) {
    await transport.sendMail({ from: env.EMAIL_FROM, ...message });
  },
};
