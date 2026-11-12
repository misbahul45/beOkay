const API_CSP = "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'";
const PAGE_CSP = "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'";

export function applySecurityHeaders(headers: Headers, options: { noStore: boolean; page?: boolean; production?: boolean }) {
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("Referrer-Policy", "no-referrer");
  headers.set("X-Frame-Options", "DENY");
  headers.set("Cross-Origin-Resource-Policy", "same-origin");
  headers.set("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=()");
  if (!headers.has("Content-Security-Policy")) headers.set("Content-Security-Policy", options.page ? PAGE_CSP : API_CSP);
  if (options.page) headers.set("X-Robots-Tag", "noindex, nofollow, noarchive");
  if (options.production) headers.set("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
  if (options.noStore) headers.set("Cache-Control", "no-store");
}
