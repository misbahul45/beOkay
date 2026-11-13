import { resolve, sep } from "node:path";
import { env } from "../../config/env.ts";

export const SITE_ROOT = resolve(import.meta.dir, "../../../public");

const SITE_CSP = [
  "default-src 'self'",
  "img-src 'self' data:",
  "style-src 'self' 'unsafe-inline'",
  "font-src 'self' data:",
  "script-src 'self'",
  "connect-src 'self'",
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'none'",
].join("; ");

export function resolveSitePath(pathname: string, root = SITE_ROOT): string | null {
  let decoded: string;
  try {
    decoded = decodeURIComponent(pathname);
  } catch {
    return null;
  }
  if (decoded.includes("\0")) return null;
  const rel = decoded === "/" ? "index.html" : decoded.replace(/^\/+/, "");
  const full = resolve(root, rel);
  return full === root || !full.startsWith(root + sep) ? null : full;
}

function headersFor(path: string) {
  const h = new Headers();
  h.set("X-Content-Type-Options", "nosniff");
  h.set("Referrer-Policy", "strict-origin-when-cross-origin");
  h.set("X-Frame-Options", "DENY");
  h.set("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=()");
  h.set("Content-Security-Policy", SITE_CSP);
  if (env.NODE_ENV === "production") h.set("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
  h.set("Cache-Control", path.includes(`${sep}assets${sep}`) ? "public, max-age=31536000, immutable" : "public, max-age=0, must-revalidate");
  return h;
}

export async function serveSite(req: Request, root = SITE_ROOT): Promise<Response | null> {
  if (req.method !== "GET" && req.method !== "HEAD") return null;
  const { pathname } = new URL(req.url);
  if (pathname === "/beokay.apk" || pathname === "/download") return Response.redirect(env.APK_DOWNLOAD_URL, 302);
  if (/^\/(api|internal|health|metrics)(\/|$)/.test(pathname)) return null;
  const path = resolveSitePath(pathname, root);
  if (!path) return null;
  const file = Bun.file(path);
  if (!(await file.exists())) return null;
  const headers = headersFor(path);
  headers.set("Content-Type", file.type);
  return new Response(req.method === "HEAD" ? null : file, { headers });
}
