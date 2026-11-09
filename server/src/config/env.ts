import { z } from "zod";

const csv = (value: string) =>
  value
    .split(",")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);

const schema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_URL: z.string().min(1),
  BETTER_AUTH_SECRET: z.string().min(32),
  BETTER_AUTH_URL: z.url(),
  TRUSTED_ORIGINS: z.string().default("").transform(csv),
  TRUST_PROXY: z
    .enum(["true", "false"])
    .default("false")
    .transform((value) => value === "true"),
  EMAIL_FROM: z.string().min(3),
  SMTP_HOST: z.string().min(1),
  SMTP_PORT: z.coerce.number().int().positive().default(587),
  SMTP_SECURE: z
    .enum(["true", "false"])
    .default("false")
    .transform((value) => value === "true"),
  SMTP_USER: z.string().optional(),
  SMTP_PASS: z.string().optional(),
  // Opsional: tanpa kunci, penyedia USDA nonaktif.
  USDA_API_KEY: z
    .string()
    .optional()
    .transform((value) => (value && value.trim() ? value.trim() : undefined)),
  // Opsional: tanpa kunci, pemindaian label (OCR) dan foto makanan nonaktif. Host dipaku di kode.
  MISTRAL_API_KEY: z
    .string()
    .optional()
    .transform((value) => (value && value.trim() ? value.trim() : undefined)),
  MISTRAL_VISION_MODEL: z
    .string()
    .optional()
    .transform((value) => (value && value.trim() ? value.trim() : "mistral-small-latest")),
  MISTRAL_OCR_MODEL: z
    .string()
    .optional()
    .transform((value) => (value && value.trim() ? value.trim() : "mistral-ocr-latest")),
});

const parsed = schema.safeParse(process.env);
if (!parsed.success) {
  const fields = parsed.error.issues.map((issue) => issue.path.join(".")).join(", ");
  throw new Error(`Invalid environment configuration: ${fields}`);
}

export const env = parsed.data;
export type Env = typeof env;
