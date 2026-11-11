import { normalizeTerm } from "../food-preferences/food-preferences.model.ts";

export type IdentityMatch = "EXACT" | "CLOSE";

const GENERIC = new Set(["dan", "atau", "dengan", "pakai", "tanpa", "yang", "segar", "mentah", "matang", "masak", "porsi"]);

export function identityTokens(text: string): string[] {
  return normalizeTerm(text)
    .split(/[^a-z0-9]+/)
    .filter((t) => t.length >= 2 && !GENERIC.has(t));
}

const sameToken = (q: string, n: string) => q === n || (q.length >= 3 && n.startsWith(q)) || (n.length >= 4 && q.startsWith(n));

export function identityMatch(query: string, name: string): IdentityMatch | null {
  const q = identityTokens(query);
  const n = identityTokens(name);
  if (q.length === 0 || n.length === 0) return null;
  const hits = q.map((t) => n.some((x) => sameToken(t, x)));
  if (!hits[0]) return null;
  const share = hits.filter(Boolean).length / q.length;
  if (share === 1) return "EXACT";
  return share >= 0.5 ? "CLOSE" : null;
}
