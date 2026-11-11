import { APIError } from "better-auth/api";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { AppError, forbidden } from "../../shared/errors/app-error.ts";
import { logEvent } from "../../shared/http/logger.ts";
import { auth } from "../auth/auth.ts";
import type { DeleteAccountInput } from "./account.schema.ts";

const WINDOW_MS = 15 * 60_000;
const MAX_ATTEMPTS = 5;
const attempts = new Map<string, number[]>();

export const accountService = {
  async delete(userId: string, headers: Headers, input: DeleteAccountInput, now = Date.now()) {
    const recent = (attempts.get(userId) ?? []).filter((t) => now - t < WINDOW_MS);
    if (recent.length >= MAX_ATTEMPTS) {
      attempts.set(userId, recent);
      throw new AppError(429, "DELETE_RATE_LIMITED", "Terlalu banyak percobaan. Coba lagi dalam 15 menit.");
    }
    attempts.set(userId, [...recent, now]);
    try {
      await auth.api.deleteUser({ body: { password: input.password }, headers });
    } catch (error) {
      if (error instanceof APIError) {
        const code = String((error.body as { code?: string } | undefined)?.code ?? "");
        if (code === "INVALID_PASSWORD") throw forbidden("INVALID_PASSWORD", "Kata sandi tidak cocok.");
        if (code === "CREDENTIAL_ACCOUNT_NOT_FOUND") throw forbidden("PASSWORD_REQUIRED", "Akun ini tidak memakai kata sandi.");
      }
      throw error;
    }
    attempts.delete(userId);
    await prisma.auditEvent.create({ data: { userId: null, eventType: "account_deleted" } });
    logEvent("info", "account_deleted", {});
    return { deleted: true };
  },
};
