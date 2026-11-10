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
  // Model bahasa untuk MENULIS teks penjelasan saran (bukan memilih saran). Tanpa MISTRAL_API_KEY, teks selalu dari templat.
  MISTRAL_AGENT_MODEL: z
    .string()
    .optional()
    .transform((value) => (value && value.trim() ? value.trim() : "mistral-small-latest")),
  // Opsional: tanpa kunci, pencarian web nonaktif.
  BRAVE_API_KEY: z
    .string()
    .optional()
    .transform((value) => (value && value.trim() ? value.trim() : undefined)),
  // Opsional: tanpa keduanya, push (FCM) nonaktif dan pengingat hanya berjalan sebagai notifikasi lokal di perangkat.
  FCM_PROJECT_ID: z
    .string()
    .optional()
    .transform((value) => (value && value.trim() ? value.trim() : undefined)),
  /** JSON akun layanan Firebase (satu baris) atau base64 dari JSON itu. Rahasia: hanya lewat env/secret, tidak pernah di berkas ter-track. */
  FCM_SERVICE_ACCOUNT_JSON: z
    .string()
    .optional()
    .transform((value) => (value && value.trim() ? value.trim() : undefined)),
  PUSH_DISPATCH_ENABLED: z
    .string()
    .default("true")
    .transform((value) => value === "true"),
  // Pekerja outbox (peristiwa agen, hasil terukur). Dimatikan pada tes yang memanggil drain() sendiri.
  OUTBOX_WORKER_ENABLED: z
    .string()
    .default("true")
    .transform((value) => value === "true"),
  // Opsional: tanpa keduanya, inferensi model Modal nonaktif. URL harus https://*.modal.run.
  MODAL_ML_URL: z.string().optional().transform((v) => (v && v.trim() ? v.trim() : undefined)),
  MODAL_ML_AUTH_TOKEN: z.string().optional().transform((v) => (v && v.trim() ? v.trim() : undefined)),
  MISTRAL_EMBEDDING_MODEL: z
    .string()
    .optional()
    .transform((value) => (value && value.trim() ? value.trim() : "mistral-embed")),
  // Opsional: unggah berkas lewat UploadThing (hanya skrip operasional; tidak dipakai jalur permintaan pengguna).
  UPLOADTHING_TOKEN: z
    .string()
    .optional()
    .transform((value) => (value && value.trim() ? value.trim() : undefined)),
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
