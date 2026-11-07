export function applySecurityHeaders(headers: Headers, options: { noStore: boolean }) {
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("Referrer-Policy", "no-referrer");
  headers.set("X-Frame-Options", "DENY");
  if (options.noStore) headers.set("Cache-Control", "no-store");
}
