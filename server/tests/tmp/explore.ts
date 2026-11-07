const API = process.env.API_BASE_URL!;
const MAIL = process.env.MAILPIT_API_URL!;
const J = { "Content-Type": "application/json", Origin: API };
const email = `u${Date.now()}@example.test`;
const password = "Sup3r-Secret-123";
type R = { status: number; headers: Headers; body: any };
async function call(method: string, path: string, opts: { body?: unknown; token?: string; ip?: string } = {}): Promise<R> {
  const headers: Record<string, string> = { ...J };
  if (opts.token) headers.Authorization = `Bearer ${opts.token}`;
  const res = await fetch(API + path, { method, headers, body: opts.body === undefined ? undefined : JSON.stringify(opts.body), redirect: "manual" });
  const text = await res.text();
  let body: any = text;
  try { body = JSON.parse(text); } catch {}
  return { status: res.status, headers: res.headers, body };
}
const show = (label: string, r: R, pick?: (b: any) => unknown) => console.log(label.padEnd(44), r.status, JSON.stringify(pick ? pick(r.body) : r.body).slice(0, 160));
async function mailTo(addr: string, nth = 0): Promise<string> {
  for (let i = 0; i < 20; i++) {
    const list: any = await (await fetch(`${MAIL}/api/v1/messages`)).json();
    const msgs = list.messages.filter((m: any) => m.To.some((t: any) => t.Address === addr));
    if (msgs.length > nth) {
      const full: any = await (await fetch(`${MAIL}/api/v1/message/${msgs[nth].ID}`)).json();
      return full.Text as string;
    }
    await Bun.sleep(300);
  }
  throw new Error("no mail for " + addr);
}
const link = (text: string) => text.match(/https?:\/\/\S+/)![0];

show("1 sign-up", await call("POST", "/api/auth/sign-up/email", { body: { name: "Rina Putri", email, password } }), (b) => ({ hasToken: !!b?.token, user: !!b?.user, code: b?.code }));
show("2 sign-up duplicate (enumeration?)", await call("POST", "/api/auth/sign-up/email", { body: { name: "X", email, password } }), (b) => ({ hasToken: !!b?.token, code: b?.code, msg: b?.message }));
show("3 sign-in before verify", await call("POST", "/api/auth/sign-in/email", { body: { email, password } }), (b) => b);
const verifyLink = link(await mailTo(email));
console.log("   verify link host/path:", new URL(verifyLink).origin + new URL(verifyLink).pathname, "callbackURL=", new URL(verifyLink).searchParams.get("callbackURL"));
const v = await fetch(verifyLink, { redirect: "manual" });
console.log("4 GET verify link".padEnd(44), v.status, v.headers.get("location"));
const si = await call("POST", "/api/auth/sign-in/email", { body: { email, password } });
const token = si.headers.get("set-auth-token") ?? "";
console.log("5 sign-in after verify".padEnd(44), si.status, "set-auth-token:", token ? "ada" : "TIDAK ADA", "| cookie:", (si.headers.get("set-cookie") ?? "").split(";")[0]!.split("=")[0]);
show("6 get-session via Bearer", await call("GET", "/api/auth/get-session", { token }), (b) => ({ user: b?.user?.email === email, verified: b?.user?.emailVerified }));
show("7 /api/me/onboarding no token", await call("GET", "/api/me/onboarding"), (b) => b.error);
show("8 /api/me/onboarding", await call("GET", "/api/me/onboarding", { token }), (b) => ({ state: b.state, steps: b.steps.map((s: any) => s.key + ":" + s.done).join(",") }));
show("9 health-profile before consent", await call("GET", "/api/me/health-profile", { token }), (b) => b.error);
show("10 policy (public)", await call("GET", "/api/consent-policies/current"), (b) => ({ v: b.version, purposes: b.purposes.map((p: any) => p.purpose + (p.required ? "*" : "")) }));
show("11 grant wrong version", await call("POST", "/api/me/consents", { token, body: { policyVersion: "0.1", purposes: ["health_data_processing"] } }), (b) => b.error);
show("12 grant required", await call("POST", "/api/me/consents", { token, body: { policyVersion: "1.0", purposes: ["health_data_processing", "descriptive_summaries"], source: "onboarding" } }), (b) => b.purposes.map((p: any) => p.purpose + ":" + p.status));
show("13 profile PATCH", await call("PATCH", "/api/me/profile", { token, body: { displayName: "Rina", birthYear: 1985 } }), (b) => ({ n: b.displayName, y: b.birthYear, c: b.completeness }));
show("14 health PUT type_2", await call("PUT", "/api/me/health-profile", { token, body: { diagnosisStatus: "diagnosed", diabetesType: "type_2", diagnosedYear: 2019, treatmentContext: ["oral_medication", "lifestyle"] } }), (b) => ({ s: b.diagnosisStatus, t: b.diabetesType, e: b.eligibilityStatus, p: b.provenance }));
show("15 health PUT invalid (type w/o diagnosis)", await call("PUT", "/api/me/health-profile", { token, body: { diagnosisStatus: "unknown", diabetesType: "type_2" } }), (b) => b.error?.code);
show("16 health PUT year before birth", await call("PUT", "/api/me/health-profile", { token, body: { diagnosisStatus: "diagnosed", diagnosedYear: 1950 } }), (b) => b.error?.code);
show("17 complete too early", await call("POST", "/api/me/onboarding/complete", { token }), (b) => b.error);
show("18 prefs PATCH invalid tz", await call("PATCH", "/api/me/preferences", { token, body: { timezone: "Mars/Olympus" } }), (b) => b.error?.code);
show("19 prefs PATCH", await call("PATCH", "/api/me/preferences", { token, body: { timezone: "Asia/Makassar", glucoseUnit: "mmol/L" } }), (b) => ({ tz: b.timezone, u: b.glucoseUnit, def: b.isDefault }));
show("20 complete", await call("POST", "/api/me/onboarding/complete", { token }), (b) => ({ state: b.state, at: !!b.completedAt }));
show("21 complete again (idempotent)", await call("POST", "/api/me/onboarding/complete", { token }), (b) => ({ state: b.state }));
show("22 withdraw required consent", await call("POST", "/api/me/consents/withdraw", { token, body: { purposes: ["health_data_processing"] } }), (b) => b.purposes.map((p: any) => p.purpose + ":" + p.status));
show("23 health GET after withdraw", await call("GET", "/api/me/health-profile", { token }), (b) => b.error?.code);
show("24 onboarding after withdraw", await call("GET", "/api/me/onboarding", { token }), (b) => ({ state: b.state, review: b.requiresConsentReview }));
show("25 profile still accessible", await call("GET", "/api/me/profile", { token }), (b) => b.displayName);
show("26 list-sessions", await call("GET", "/api/auth/list-sessions", { token }), (b) => ({ n: b.length, ip: b[0]?.ipAddress }));
show("27 malformed JSON", await call("PATCH", "/api/me/profile", { token, body: undefined }), (b) => b.error?.code);
// password reset
show("28 request-password-reset (known)", await call("POST", "/api/auth/request-password-reset", { body: { email } }), (b) => b);
show("29 request-password-reset (unknown)", await call("POST", "/api/auth/request-password-reset", { body: { email: "nobody@example.test" } }), (b) => b);
const resetText = await mailTo(email, 0);
const resetMail = await (async () => { for (let i = 0; i < 20; i++) { const list: any = await (await fetch(`${MAIL}/api/v1/messages`)).json(); const m = list.messages.filter((x: any) => x.To.some((t: any) => t.Address === email) && /Atur ulang/.test(x.Subject))[0]; if (m) return (await (await fetch(`${MAIL}/api/v1/message/${m.ID}`)).json() as any).Text as string; await Bun.sleep(300); } throw new Error("no reset mail"); })();
const resetUrl = new URL(link(resetMail));
console.log("   reset link:", resetUrl.origin + resetUrl.pathname, "token?", resetUrl.searchParams.has("token"));
const page = await fetch(resetUrl);
console.log("30 GET reset page".padEnd(44), page.status, page.headers.get("content-type"), "| CSP:", !!page.headers.get("content-security-policy"));
show("31 reset with token", await call("POST", "/api/auth/reset-password", { body: { newPassword: "Brand-New-Pass-456", token: resetUrl.searchParams.get("token") } }), (b) => b);
show("32 old session after reset", await call("GET", "/api/me/profile", { token }), (b) => b.error?.code ?? "masih valid");
show("33 sign-in old password", await call("POST", "/api/auth/sign-in/email", { body: { email, password } }), (b) => b.code);
show("34 sign-in new password", await call("POST", "/api/auth/sign-in/email", { body: { email, password: "Brand-New-Pass-456" } }), (b) => ({ ok: !!b.token }));
// rate limit
const codes: number[] = [];
for (let i = 0; i < 8; i++) codes.push((await call("POST", "/api/auth/sign-in/email", { body: { email, password: "wrong-wrong-wrong" } })).status);
console.log("35 rate limit sign-in x8".padEnd(44), codes.join(","));
const verifiedPage = await fetch(API + "/auth/verified");
console.log("36 GET /auth/verified".padEnd(44), verifiedPage.status);
