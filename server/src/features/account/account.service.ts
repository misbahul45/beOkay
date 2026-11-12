import { APIError } from "better-auth/api";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { AppError, forbidden } from "../../shared/errors/app-error.ts";
import { logEvent } from "../../shared/http/logger.ts";
import { auth } from "../auth/auth.ts";
import type { DeleteAccountInput } from "./account.schema.ts";
import { rateWindow } from "../../shared/http/rate-window.ts";

const WINDOW_MS = 15 * 60_000;
const MAX_ATTEMPTS = 5;
const attempts = rateWindow(WINDOW_MS, MAX_ATTEMPTS);

export const accountService = {
  async delete(userId: string, headers: Headers, input: DeleteAccountInput, now = Date.now()) {
    if (attempts.full(userId, now)) throw new AppError(429, "DELETE_RATE_LIMITED", "Terlalu banyak percobaan. Coba lagi dalam 15 menit.");
    attempts.record(userId, now);
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
    attempts.clear(userId);
    await prisma.auditEvent.create({ data: { userId: null, eventType: "account_deleted" } });
    logEvent("info", "account_deleted", {});
    return { deleted: true };
  },
};
