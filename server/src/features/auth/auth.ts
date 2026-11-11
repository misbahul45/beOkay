import { betterAuth } from "better-auth";
import { prismaAdapter } from "better-auth/adapters/prisma";
import { bearer } from "better-auth/plugins/bearer";
import { env } from "../../config/env.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { accountDeletedEmail, passwordResetEmail, verificationEmail } from "../../infrastructure/email/email-templates.ts";
import { smtpEmailSender } from "../../infrastructure/email/smtp-email-sender.ts";
import type { EmailMessage } from "../../infrastructure/email/email-sender.ts";
import { logEvent } from "../../shared/http/logger.ts";

export const CLIENT_IP_HEADER = "x-beokay-client-ip";

function dispatchEmail(kind: string, message: EmailMessage) {
  void smtpEmailSender.send(message).catch(() => logEvent("error", "email_send_failed", { kind }));
}

export const auth = betterAuth({
  secret: env.BETTER_AUTH_SECRET,
  baseURL: env.BETTER_AUTH_URL,
  trustedOrigins: env.TRUSTED_ORIGINS,
  database: prismaAdapter(prisma, { provider: "postgresql" }),
  advanced: {
    database: { generateId: "uuid" },
    ipAddress: { ipAddressHeaders: [CLIENT_IP_HEADER] },
  },
  user: {
    modelName: "users",
    deleteUser: {
      enabled: true,
      afterDelete: async (user) => dispatchEmail("account_deleted", { to: user.email, ...accountDeletedEmail() }),
    },
  },
  session: {
    modelName: "sessions",
    expiresIn: 60 * 60 * 24 * 7,
    updateAge: 60 * 60 * 24,
  },
  account: { modelName: "accounts" },
  verification: { modelName: "verifications" },
  emailAndPassword: {
    enabled: true,
    minPasswordLength: 10,
    maxPasswordLength: 128,
    requireEmailVerification: true,
    autoSignIn: false,
    resetPasswordTokenExpiresIn: 60 * 60,
    revokeSessionsOnPasswordReset: true,
    sendResetPassword: async ({ token, user }) => {
      const url = `${env.BETTER_AUTH_URL}/auth/reset-password?token=${encodeURIComponent(token)}`;
      dispatchEmail("password_reset", { to: user.email, ...passwordResetEmail(url) });
    },
  },
  emailVerification: {
    sendOnSignUp: true,
    sendOnSignIn: true,
    autoSignInAfterVerification: false,
    expiresIn: 60 * 60,
    sendVerificationEmail: async ({ user, url }) => {
      const link = new URL(url);
      link.searchParams.set("callbackURL", `${env.BETTER_AUTH_URL}/auth/verified`);
      dispatchEmail("email_verification", { to: user.email, ...verificationEmail(link.toString()) });
    },
  },
  rateLimit: {
    enabled: true,
    window: 60,
    max: 120,
    storage: "memory",
    customRules: {
      "/sign-in/email": { window: 60, max: 5 },
      "/sign-up/email": { window: 60, max: 5 },
      "/request-password-reset": { window: 60, max: 3 },
      "/reset-password": { window: 60, max: 5 },
      "/send-verification-email": { window: 60, max: 3 },
      "/change-password": { window: 60, max: 5 },
    },
  },
  plugins: [bearer()],
});
