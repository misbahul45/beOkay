import { betterAuth } from "better-auth";
import { prismaAdapter } from "better-auth/adapters/prisma";
import { prisma } from "../infrastructure/database/prisma.ts";

const secret = process.env.BETTER_AUTH_SECRET;
if (!secret || secret.length < 32) {
  throw new Error("BETTER_AUTH_SECRET must be set (min 32 chars)");
}

export const auth = betterAuth({
  secret,
  baseURL: process.env.BETTER_AUTH_URL ?? "http://localhost:3000",
  database: prismaAdapter(prisma, { provider: "postgresql" }),
  // Blueprint: PK UUID + nama tabel plural (users). Kolom auth tetap camelCase bawaan
  // library; keputusan penamaan kolom menunggu Data Dictionary.
  advanced: { database: { generateId: "uuid" } },
  user: { modelName: "users" },
  session: { modelName: "sessions" },
  account: { modelName: "accounts" },
  verification: { modelName: "verifications" },
  // Email + password saja. Verifikasi email dan reset password menunggu
  // penyedia email (belum diputuskan) — jangan diaktifkan tanpa sender.
  emailAndPassword: { enabled: true },
});
