const API = process.env.API_BASE_URL!;
const j = { "Content-Type": "application/json" };
const r = async (label: string, method: string, path: string, headers: Record<string, string> = {}, body?: unknown) => {
  const res = await fetch(API + path, { method, headers: { ...j, ...headers }, body: body === undefined ? undefined : JSON.stringify(body), redirect: "manual" });
  const t = await res.text();
  console.log(label.padEnd(46), res.status, t.slice(0, 90).replace(/\s+/g, " "));
};
await r("sign-in tanpa Origin (klien native)", "POST", "/api/auth/sign-in/email", {}, { email: "x@example.test", password: "wrong-wrong-wrong" });
await r("sign-in Origin jahat", "POST", "/api/auth/sign-in/email", { Origin: "http://evil.example" }, { email: "x@example.test", password: "wrong-wrong-wrong" });
for (const [m, p] of [["GET", "/api/me/onboarding"], ["PATCH", "/api/me/onboarding"], ["POST", "/api/me/onboarding/complete"], ["GET", "/api/me/profile"], ["PATCH", "/api/me/profile"], ["GET", "/api/me/health-profile"], ["PUT", "/api/me/health-profile"], ["PATCH", "/api/me/health-profile"], ["GET", "/api/me/preferences"], ["PATCH", "/api/me/preferences"], ["GET", "/api/me/consents"], ["POST", "/api/me/consents"], ["POST", "/api/me/consents/withdraw"]] as const) {
  await r(`tanpa token ${m} ${p}`, m, p, {}, m === "GET" ? undefined : {});
}
await r("token ngawur", "GET", "/api/me/profile", { Authorization: "Bearer not-a-real-token" });
await r("metode tak didukung DELETE /api/me/profile", "DELETE", "/api/me/profile");
await r("rute tak ada", "GET", "/api/nope");
await r("bukan JSON content-type", "POST", "/api/me/consents", { "Content-Type": "text/plain", Authorization: "Bearer x" }, undefined);
const big = await fetch(API + "/api/me/consents", { method: "POST", headers: { ...j, "Content-Length": "999999" }, body: "{}" }).catch(() => null);
console.log("payload besar".padEnd(46), big?.status ?? "koneksi ditolak");
