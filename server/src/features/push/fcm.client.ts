import { createSign } from "node:crypto";

const TOKEN_URI = "https://oauth2.googleapis.com/token";
const FCM_HOST = "fcm.googleapis.com";
const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

export type PushMessage = {
  token: string;
  title: string;
  body: string;
  /** Hanya nilai string. Tidak boleh memuat data kesehatan. */
  data?: Record<string, string>;
  collapseKey?: string;
  ttlSeconds?: number;
  androidChannelId?: string;
};

export type PushReceipt = {
  status: "sent" | "failed" | "invalid_token";
  providerMessageId?: string;
  errorCode?: string;
  httpStatus?: number;
  /** true bila perangkat harus dinonaktifkan (token tidak berlaku lagi). */
  shouldDeactivate: boolean;
};

type ServiceAccount = { client_email: string; private_key: string; token_uri?: string };

const b64url = (v: Buffer | string) => Buffer.from(v).toString("base64url");

/** Menerima JSON mentah atau base64 dari JSON. Mengembalikan null bila tidak valid (tanpa mencetak isinya). */
export function parseServiceAccount(raw: string | undefined): ServiceAccount | null {
  if (!raw) return null;
  const candidates = [raw, Buffer.from(raw, "base64").toString("utf8")];
  for (const text of candidates) {
    try {
      const j = JSON.parse(text) as Partial<ServiceAccount> & { type?: string };
      if (typeof j.client_email === "string" && typeof j.private_key === "string" && j.private_key.includes("PRIVATE KEY")) return { client_email: j.client_email, private_key: j.private_key, token_uri: j.token_uri };
    } catch {
      // coba kandidat berikutnya
    }
  }
  return null;
}

export function classifyFcmError(status: number, body: unknown): { code: string; invalidToken: boolean } {
  const err = (body as { error?: { status?: string; details?: { errorCode?: string }[] } } | undefined)?.error;
  const code = err?.details?.find((d) => d.errorCode)?.errorCode ?? err?.status ?? `HTTP_${status}`;
  // UNREGISTERED/NOT_FOUND: token tidak berlaku lagi. SENDER_ID_MISMATCH: token milik proyek/aplikasi lain.
  const invalidToken = code === "UNREGISTERED" || code === "NOT_FOUND" || code === "SENDER_ID_MISMATCH";
  return { code: String(code).slice(0, 100), invalidToken };
}

/**
 * Klien FCM HTTP v1 tanpa dependensi tambahan. Host OAuth dan FCM dipaku; JWT RS256 ditandatangani dengan kunci
 * akun layanan; token akses di-cache. Kunci tidak pernah dicatat. Tanpa konfigurasi klien melapor `configured:false`.
 */
export function createFcmClient(
  config: { projectId: string | undefined; serviceAccountJson: string | undefined },
  deps: { fetchImpl?: typeof fetch; now?: () => number } = {},
) {
  const fetchImpl = deps.fetchImpl ?? fetch;
  const now = deps.now ?? Date.now;
  const account = parseServiceAccount(config.serviceAccountJson);
  const configured = Boolean(config.projectId && account);
  let cached: { token: string; expiresAt: number } | null = null;

  async function accessToken(): Promise<string> {
    if (cached && cached.expiresAt > now() + 60_000) return cached.token;
    if (!account) throw new Error("FCM_NOT_CONFIGURED");
    if (account.token_uri && account.token_uri !== TOKEN_URI) throw new Error("FCM_TOKEN_URI_NOT_ALLOWED");
    const iat = Math.floor(now() / 1000);
    const claims = { iss: account.client_email, scope: SCOPE, aud: TOKEN_URI, iat, exp: iat + 3600 };
    const unsigned = `${b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.${b64url(JSON.stringify(claims))}`;
    const signature = createSign("RSA-SHA256").update(unsigned).sign(account.private_key);
    const res = await fetchImpl(TOKEN_URI, {
      method: "POST",
      redirect: "error",
      signal: AbortSignal.timeout(8000),
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${unsigned}.${b64url(signature)}` }),
    });
    if (!res.ok) throw new Error(`FCM_AUTH_${res.status}`);
    const json = (await res.json()) as { access_token?: string; expires_in?: number };
    if (!json.access_token) throw new Error("FCM_AUTH_EMPTY");
    cached = { token: json.access_token, expiresAt: now() + (json.expires_in ?? 3600) * 1000 };
    return cached.token;
  }

  return {
    configured,
    /** `validateOnly` memeriksa kredensial dan bentuk pesan tanpa mengirim apa pun ke perangkat. */
    async send(message: PushMessage, opts: { validateOnly?: boolean } = {}): Promise<PushReceipt> {
      if (!configured) return { status: "failed", errorCode: "FCM_NOT_CONFIGURED", shouldDeactivate: false };
      let res: Response;
      try {
        const bearer = await accessToken();
        res = await fetchImpl(`https://${FCM_HOST}/v1/projects/${encodeURIComponent(config.projectId!)}/messages:send`, {
          method: "POST",
          redirect: "error",
          signal: AbortSignal.timeout(8000),
          headers: { authorization: `Bearer ${bearer}`, "content-type": "application/json" },
          body: JSON.stringify({
            validate_only: opts.validateOnly || undefined,
            message: {
              token: message.token,
              notification: { title: message.title, body: message.body },
              data: message.data,
              android: {
                priority: "HIGH",
                ttl: `${message.ttlSeconds ?? 3600}s`,
                collapse_key: message.collapseKey,
                notification: { channel_id: message.androidChannelId ?? "beokay_reminders", icon: "ic_stat_beokay", color: "#0B4F5E", visibility: "PRIVATE" },
              },
            },
          }),
        });
      } catch (e) {
        const msg = e instanceof Error ? e.message : "NETWORK";
        if (msg.startsWith("FCM_AUTH_")) cached = null;
        return { status: "failed", errorCode: msg.startsWith("FCM_") ? msg : "NETWORK_ERROR", shouldDeactivate: false };
      }
      const text = await res.text();
      let body: unknown;
      try {
        body = text ? JSON.parse(text) : undefined;
      } catch {
        body = undefined;
      }
      if (res.ok) return { status: "sent", providerMessageId: (body as { name?: string } | undefined)?.name, httpStatus: res.status, shouldDeactivate: false };
      if (res.status === 401 || res.status === 403) cached = null;
      const { code, invalidToken } = classifyFcmError(res.status, body);
      return { status: invalidToken ? "invalid_token" : "failed", errorCode: code, httpStatus: res.status, shouldDeactivate: invalidToken };
    },
  };
}

export type FcmClient = ReturnType<typeof createFcmClient>;
