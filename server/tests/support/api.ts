import { prisma } from "../../src/infrastructure/database/prisma.ts";

export const api = process.env.API_BASE_URL ?? "";
export const requireIsolatedApi = () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated test API required");
};

export const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });

export const J = async (r: Response) => (await r.json()) as any;
export const op = () => crypto.randomUUID();
export const hash = () => (crypto.randomUUID() + crypto.randomUUID()).replace(/-/g, "");

export function actors() {
  const users: string[] = [];
  async function actor(purposes: string[] = ["health_data_processing", "descriptive_summaries"], opts: { ageDays?: number; email?: string } = {}) {
    const id = crypto.randomUUID(), token = crypto.randomUUID();
    users.push(id);
    const email = opts.email ?? `t-${id}@example.test`;
    await prisma.users.create({ data: { id, name: "Fixture", email, emailVerified: true, createdAt: new Date(Date.now() - (opts.ageDays ?? 30) * 86_400_000), updatedAt: new Date() } });
    await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
    if (purposes.length) {
      const policy = await J(await call("/api/consent-policies/current", token));
      await call("/api/me/consents", token, { policyVersion: policy.version, purposes });
    }
    await call("/api/me/preferences", token, { timezone: "Asia/Jakarta" }, "PATCH");
    return { id, token, email };
  }
  const cleanup = () => prisma.users.deleteMany({ where: { id: { in: users } } });
  return { actor, cleanup, users };
}

export const wib = (date: string, hh = 12, mm = 0) => new Date(`${date}T${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}:00+07:00`);
export const todayWib = () => new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Jakarta" }).format(new Date());
export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
