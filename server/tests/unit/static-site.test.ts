import { expect, test } from "bun:test";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { resolveSitePath, serveSite } from "../../src/shared/http/static-site.ts";

const root = mkdtempSync(join(tmpdir(), "site-"));
mkdirSync(join(root, "assets"));
writeFileSync(join(root, "index.html"), "<!doctype html><title>beOkay</title>");
writeFileSync(join(root, "assets", "app-1.js"), "console.log(1)");
const get = (p: string, method = "GET") => serveSite(new Request("http://x" + p, { method }), root);

test("path situs: akar ke index.html, traversal dan byte nol ditolak", () => {
  expect(resolveSitePath("/", root)).toBe(join(root, "index.html"));
  expect(resolveSitePath("/assets/app-1.js", root)).toBe(join(root, "assets", "app-1.js"));
  expect(resolveSitePath("/../etc/passwd", root)).toBeNull();
  expect(resolveSitePath("/%2e%2e/%2e%2e/etc/passwd", root)).toBeNull();
  expect(resolveSitePath("/a%00b", root)).toBeNull();
  expect(resolveSitePath("/%E0%A4%A", root)).toBeNull();
});

test("situs: halaman dan aset disajikan dengan header; API, metode lain, dan berkas hilang diteruskan", async () => {
  const home = (await get("/"))!;
  expect(home.status).toBe(200);
  expect(home.headers.get("content-type")).toContain("text/html");
  expect(home.headers.get("cache-control")).toBe("public, max-age=0, must-revalidate");
  expect(home.headers.get("content-security-policy")).toContain("default-src 'self'");
  expect(await home.text()).toContain("beOkay");
  expect((await get("/assets/app-1.js"))!.headers.get("cache-control")).toContain("immutable");
  expect((await get("/", "HEAD"))!.status).toBe(200);
  expect(await get("/", "POST")).toBeNull();
  expect(await get("/api/me")).toBeNull();
  expect(await get("/health")).toBeNull();
  expect(await get("/internal/jobs/tick")).toBeNull();
  expect(await get("/tidak-ada.html")).toBeNull();
  const apk = (await get("/beokay.apk"))!;
  expect(apk.status).toBe(302);
  expect(apk.headers.get("location")).toMatch(/\.apk$/);
});
