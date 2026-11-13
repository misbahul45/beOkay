export const RETRIEVAL_VERSION = "retrieval-v1";

export const CERTAINTY = ["verified", "reported", "estimated", "insufficient", "unknown"] as const;
export type Certainty = (typeof CERTAINTY)[number];

export type ProvenanceKind =
  | { kind: "knowledge"; reviewStatus: string }
  | { kind: "food_reference"; status: string }
  | { kind: "web" }
  | { kind: "record"; qualityStatus: string | null }
  | { kind: "device"; status: string }
  | { kind: "projection"; observedDays: number; windowDays: number }
  | { kind: "none" };

export function certaintyOf(p: ProvenanceKind): Certainty {
  switch (p.kind) {
    case "knowledge":
      return p.reviewStatus === "REVIEWED" ? "verified" : "insufficient";
    case "food_reference":
      return p.status === "verified_auto" || p.status === "curated" ? "verified" : "estimated";
    case "web":
      return "estimated";
    case "record":
      if (p.qualityStatus === "user_reported") return "reported";
      if (p.qualityStatus === "device_reported") return "estimated";
      return p.qualityStatus === null ? "unknown" : "insufficient";
    case "device":
      return p.status === "OK" || p.status === "PARTIAL" ? "estimated" : p.status === "NO_DATA" || p.status === "STALE" ? "insufficient" : "unknown";
    case "projection":
      return p.observedDays === 0 ? "insufficient" : p.observedDays / Math.max(1, p.windowDays) >= 0.6 ? "reported" : "insufficient";
    case "none":
      return "unknown";
  }
}

export function normalizeText(t: string): string {
  return t
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9%\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export type Section = { heading: string; text: string };

export function chunkMarkdown(body: string): Section[] {
  const out: Section[] = [];
  let cur: Section | null = null;
  for (const raw of body.split("\n")) {
    const line = raw.trim();
    if (line.startsWith("## ")) {
      cur = { heading: line.slice(3).trim(), text: "" };
      out.push(cur);
      continue;
    }
    if (!line) continue;
    if (!cur) {
      cur = { heading: "", text: "" };
      out.push(cur);
    }
    cur.text += (cur.text ? " " : "") + line.replace(/^- /, "");
  }
  return out.filter((s) => s.text.length > 0);
}

export function sourceOf(sections: Section[]): string {
  return sections.find((s) => s.heading.toLowerCase() === "sumber")?.text ?? "Tidak disebutkan";
}

export type Ranked = { id: string; score: number };

export function fuse(lists: Ranked[][], k = 60): { id: string; score: number; ranks: number[] }[] {
  const acc = new Map<string, { id: string; score: number; ranks: number[] }>();
  lists.forEach((list, li) =>
    list.forEach((r, i) => {
      const e = acc.get(r.id) ?? { id: r.id, score: 0, ranks: lists.map(() => -1) };
      e.score += 1 / (k + i + 1);
      e.ranks[li] = i;
      acc.set(r.id, e);
    }),
  );
  return [...acc.values()].sort((a, b) => b.score - a.score || a.id.localeCompare(b.id));
}

export const MIN_LEXICAL_SCORE = 0.3;
export const MIN_VECTOR_SCORE = 0.75;

export type CoverageDecision = { status: "ANSWER" | "ABSTAIN"; reason: "MATCHED" | "NO_CANDIDATES" | "LOW_SCORE" | "ONLY_UNREVIEWED_IN_PRODUCTION" };

export function assessCoverage(best: { lexical: number | null; vector: number | null } | null, opts: { reviewedCount: number; draftsAllowed: boolean }): CoverageDecision {
  if (!best) return { status: "ABSTAIN", reason: "NO_CANDIDATES" };
  const strong = (best.lexical ?? 0) >= MIN_LEXICAL_SCORE || (best.vector ?? 0) >= MIN_VECTOR_SCORE;
  if (!strong) return { status: "ABSTAIN", reason: "LOW_SCORE" };
  if (!opts.draftsAllowed && opts.reviewedCount === 0) return { status: "ABSTAIN", reason: "ONLY_UNREVIEWED_IN_PRODUCTION" };
  return { status: "ANSWER", reason: "MATCHED" };
}
