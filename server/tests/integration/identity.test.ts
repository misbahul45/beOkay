import { expect, test } from "bun:test";

const api = process.env.API_BASE_URL;
const mail = process.env.MAILPIT_API_URL;

test("identity journey persists and enforces consent and sessions", async () => {
  if (!api || !mail || process.env.NODE_ENV !== "test") throw new Error("Isolated test API and Mailpit are required");
  const password = crypto.randomUUID();
  const suffix = crypto.randomUUID();
  const email = `identity-${suffix}@example.test`;
  const call = (path: string, options: { method?: string; body?: object; token?: string } = {}) =>
    fetch(`${api}${path}`, {
      method: options.method ?? "GET",
      headers: {
        ...(options.body ? { "content-type": "application/json" } : {}),
        ...(options.token ? { authorization: `Bearer ${options.token}` } : {}),
      },
      body: options.body ? JSON.stringify(options.body) : undefined,
      redirect: "manual",
    });

  expect((await call("/api/me/profile")).status).toBe(401);
  expect((await call("/api/me/today")).status).toBe(401);
  expect((await call("/api/auth/sign-up/email", { method: "POST", body: { name: "Test User", email, password } })).status).toBe(200);
  expect((await call("/api/auth/sign-in/email", { method: "POST", body: { email, password } })).status).toBe(403);

  let verificationUrl: string | undefined;
  for (let attempt = 0; attempt < 40 && !verificationUrl; attempt++) {
    const listing = await (await fetch(`${mail}/api/v1/messages`)).json() as { messages: { ID: string; To: { Address: string }[] }[] };
    const message = listing.messages.find((item) => item.To.some((to) => to.Address === email));
    if (message) {
      const detail = await (await fetch(`${mail}/api/v1/message/${message.ID}`)).json() as { Text: string };
      verificationUrl = detail.Text.match(/https?:\/\/[^\s<>]+/)?.[0];
    }
    if (!verificationUrl) await Bun.sleep(250);
  }
  expect(verificationUrl).toBeDefined();
  expect((await fetch(verificationUrl!, { redirect: "manual" })).status).toBe(302);
  const login = await call("/api/auth/sign-in/email", { method: "POST", body: { email, password } });
  expect(login.status).toBe(200);
  const token = login.headers.get("set-auth-token");
  expect(token).toBeTruthy();
  const auth = { token: token! };
  expect((await call("/api/me/health-profile", auth)).status).toBe(403);
  expect((await call("/api/me/today", auth)).status).toBe(403);
  const policy = await (await call("/api/consent-policies/current")).json() as { version: string };
  expect((await call("/api/me/consents", { ...auth, method: "POST", body: { policyVersion: policy.version, purposes: ["health_data_processing", "descriptive_summaries"], source: "onboarding" } })).status).toBe(200);
  expect((await call("/api/me/profile", { ...auth, method: "PATCH", body: { displayName: "Test User", birthYear: 1985 } })).status).toBe(200);
  expect((await call("/api/me/health-profile", { ...auth, method: "PUT", body: { diagnosisStatus: "unknown" } })).status).toBe(200);
  expect((await call("/api/me/preferences", { ...auth, method: "PATCH", body: { timezone: "Asia/Jakarta", glucoseUnit: "mmol/L" } })).status).toBe(200);
  expect((await call("/api/me/onboarding/complete", { ...auth, method: "POST", body: {} })).status).toBe(200);
  expect((await (await call("/api/me/onboarding", auth)).json() as { state: string }).state).toBe("COMPLETED");
  expect((await (await call("/api/me/preferences", auth)).json() as { glucoseUnit: string }).glucoseUnit).toBe("mmol/L");
  const today = await call("/api/me/today?userId=another-account", auth);
  expect(today.status).toBe(200);
  expect(today.headers.get("cache-control")).toContain("no-store");
  const overview = await today.json() as { displayName: string; timezone: string; glucoseUnit: string; metrics: { value: unknown }[] };
  expect(overview.displayName).toBe("Test User");
  expect(overview.timezone).toBe("Asia/Jakarta");
  expect(overview.glucoseUnit).toBe("mmol/L");
  expect(overview.metrics.filter((item: any) => !["nutrition", "glucose", "activity"].includes(item.domain)).every((item) => item.value === null)).toBe(true);
  const secondEmail = `today-second-${suffix}@example.test`;
  expect((await call("/api/auth/sign-up/email", { method: "POST", body: { name: "Second User", email: secondEmail, password } })).status).toBe(200);
  let secondVerification: string | undefined;
  for (let attempt = 0; attempt < 40 && !secondVerification; attempt++) {
    const listing = await (await fetch(`${mail}/api/v1/messages`)).json() as { messages: { ID: string; To: { Address: string }[] }[] };
    const message = listing.messages.find((item) => item.To.some((to) => to.Address === secondEmail));
    if (message) {
      const detail = await (await fetch(`${mail}/api/v1/message/${message.ID}`)).json() as { Text: string };
      secondVerification = detail.Text.match(/https?:\/\/[^\s<>]+/)?.[0];
    }
    if (!secondVerification) await Bun.sleep(250);
  }
  expect(secondVerification).toBeDefined();
  await fetch(secondVerification!, { redirect: "manual" });
  const secondLogin = await call("/api/auth/sign-in/email", { method: "POST", body: { email: secondEmail, password } });
  const secondToken = secondLogin.headers.get("set-auth-token");
  expect(secondToken).toBeTruthy();
  const secondAuth = { token: secondToken! };
  expect((await call("/api/me/today", secondAuth)).status).toBe(403);
  await call("/api/me/consents", { ...secondAuth, method: "POST", body: { policyVersion: policy.version, purposes: ["health_data_processing", "descriptive_summaries"] } });
  await call("/api/me/preferences", { ...secondAuth, method: "PATCH", body: { timezone: "Pacific/Honolulu", glucoseUnit: "mg/dL" } });
  const secondToday = await (await call("/api/me/today", secondAuth)).json() as { displayName: string; timezone: string; glucoseUnit: string };
  expect(secondToday.displayName).toBe("Second User");
  expect(secondToday.timezone).toBe("Pacific/Honolulu");
  expect(secondToday.glucoseUnit).toBe("mg/dL");
  expect((await (await call("/api/me/today", auth)).json() as { glucoseUnit: string }).glucoseUnit).toBe("mmol/L");
  expect((await call("/api/me/consents/withdraw", { ...auth, method: "POST", body: { purposes: ["descriptive_summaries"] } })).status).toBe(200);
  expect((await call("/api/me/today", auth)).status).toBe(403);
  expect((await call("/api/me/consents", { ...auth, method: "POST", body: { policyVersion: policy.version, purposes: ["descriptive_summaries"] } })).status).toBe(200);
  expect((await call("/api/me/consents/withdraw", { ...auth, method: "POST", body: { purposes: ["health_data_processing"] } })).status).toBe(200);
  expect((await call("/api/me/health-profile", auth)).status).toBe(403);
  expect((await call("/api/me/today", auth)).status).toBe(403);
  expect((await call("/api/me/profile", auth)).status).toBe(200);
  expect((await call("/api/auth/sign-out", { ...auth, method: "POST", body: {} })).status).toBe(200);
  expect((await call("/api/me/profile", auth)).status).toBe(401);
  expect((await call("/api/me/today", auth)).status).toBe(401);
}, 30000);
