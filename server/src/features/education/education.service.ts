import { createHash } from "node:crypto";
import { env } from "../../config/env.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { notFound, unprocessable } from "../../shared/errors/app-error.ts";
import { logEvent } from "../../shared/http/logger.ts";
import { EDUCATION_MODULES, type EducationContent } from "../../content/education/modules.ts";

export const EDUCATION_VERSION = "education-v1";

export const SAFETY_MODULES: Record<string, string[]> = {
  URGENT_SYMPTOM: ["hipoglikemia", "saat-sakit"],
  GLUCOSE_EXTREME: ["hipoglikemia", "saat-sakit"],
  SYMPTOM_REVIEW: ["perawatan-kaki", "saat-sakit"],
  INJURY_OR_PAIN: ["aktivitas-aman"],
  INTENSITY_ESCALATION: ["aktivitas-aman"],
  MEDICATION_ADVICE: ["obat-bertanya-dokter"],
  DIAGNOSIS_REQUEST: ["mengenal-dmt2", "cek-gula-mandiri"],
  HEALTH_CLAIM_REQUEST: ["karbohidrat-porsi", "label-gizi"],
  EXTREME_RESTRICTION: ["karbohidrat-porsi", "puasa-ramadan"],
};

export function contentHash(m: Pick<EducationContent, "title" | "summary" | "topics" | "readMinutes" | "body">) {
  return createHash("sha256").update(JSON.stringify([m.title, m.summary, [...m.topics].sort(), m.readMinutes, m.body])).digest("hex");
}

export type Section = { heading: string; paragraphs: string[]; bullets: string[] };

export function parseBody(body: string): Section[] {
  const out: Section[] = [];
  let cur: Section | null = null;
  for (const raw of body.split("\n")) {
    const line = raw.trim();
    if (!line) continue;
    if (line.startsWith("## ")) {
      cur = { heading: line.slice(3).trim(), paragraphs: [], bullets: [] };
      out.push(cur);
      continue;
    }
    if (!cur) {
      cur = { heading: "", paragraphs: [], bullets: [] };
      out.push(cur);
    }
    if (line.startsWith("- ")) cur.bullets.push(line.slice(2).trim());
    else cur.paragraphs.push(line);
  }
  return out;
}

type Row = Awaited<ReturnType<typeof prisma.educationModule.findMany>>[number];

const listView = (r: Row) => ({
  key: r.key,
  version: r.version,
  title: r.title,
  summary: r.summary,
  topics: r.topics,
  readMinutes: r.readMinutes,
  reviewStatus: r.reviewStatus as "DRAFT" | "REVIEWED",
  reviewedAt: r.reviewedAt?.toISOString() ?? null,
});

const detailView = (r: Row) => ({
  ...listView(r),
  sections: parseBody(r.body),
  authoredOn: r.authoredOn.toISOString().slice(0, 10),
  reviewedBy: r.reviewedBy,
  notice: r.reviewStatus === "REVIEWED" ? "Bacaan umum, bukan pengganti saran tenaga kesehatanmu." : "Draf: belum ditinjau klinisi. Bacaan umum, bukan pengganti saran tenaga kesehatanmu.",
});

export function createEducationService(opts: { includeDrafts: () => boolean; modules?: EducationContent[] }) {
  const modules = () => opts.modules ?? EDUCATION_MODULES;
  const statuses = () => (opts.includeDrafts() ? ["REVIEWED", "DRAFT"] : ["REVIEWED"]);

  async function servable(keys?: string[]) {
    const rows = await prisma.educationModule.findMany({ where: { reviewStatus: { in: statuses() }, ...(keys ? { key: { in: keys } } : {}) }, orderBy: [{ key: "asc" }, { version: "desc" }] });
    const latest = new Map<string, Row>();
    for (const r of rows) if (!latest.has(r.key)) latest.set(r.key, r);
    return latest;
  }

  const order = () => new Map(modules().map((m, i) => [m.key, i]));

  return {
    async sync() {
      const result = { created: 0, updated: 0, unchanged: 0, rejected: [] as string[] };
      for (const m of modules()) {
        const hash = contentHash(m);
        const existing = await prisma.educationModule.findUnique({ where: { key_version: { key: m.key, version: m.version } } });
        const data = { title: m.title, summary: m.summary, topics: m.topics, readMinutes: m.readMinutes, body: m.body, contentHash: hash, authoredOn: new Date(m.authoredOn + "T00:00:00Z") };
        if (!existing) {
          await prisma.educationModule.create({ data: { key: m.key, version: m.version, reviewStatus: "DRAFT", ...data } });
          result.created++;
        } else if (existing.contentHash === hash) {
          result.unchanged++;
        } else if (existing.reviewStatus === "DRAFT") {
          await prisma.educationModule.update({ where: { id: existing.id }, data });
          result.updated++;
        } else {
          result.rejected.push(`${m.key}@${m.version}`);
        }
      }
      if (result.rejected.length) logEvent("warn", "education_content_changed_without_version", { modules: result.rejected.join(",") });
      return result;
    },

    async list() {
      const rows = [...(await servable()).values()];
      const pos = order();
      rows.sort((a, b) => (pos.get(a.key) ?? 99) - (pos.get(b.key) ?? 99));
      return { version: EDUCATION_VERSION, items: rows.map(listView), includesDrafts: opts.includeDrafts() };
    },

    async get(key: string) {
      const row = (await servable([key])).get(key);
      if (!row) throw notFound("EDUCATION_MODULE_NOT_FOUND", "Modul tidak ditemukan.");
      return detailView(row);
    },

    async forSafety(code: string) {
      const keys = SAFETY_MODULES[code];
      if (!keys?.length) return [];
      const found = await servable(keys);
      return keys.map((k) => found.get(k)).filter((r): r is Row => Boolean(r)).map((r) => ({ key: r.key, title: r.title, readMinutes: r.readMinutes, reviewStatus: r.reviewStatus as "DRAFT" | "REVIEWED" }));
    },

    async review(key: string, version: number, reviewer: string, now = new Date()) {
      const row = await prisma.educationModule.findUnique({ where: { key_version: { key, version } } });
      if (!row) throw notFound("EDUCATION_MODULE_NOT_FOUND", "Modul tidak ditemukan.");
      if (reviewer.trim().length < 2) throw unprocessable("REVIEWER_REQUIRED", "Nama peninjau wajib diisi.");
      return prisma.educationModule.update({ where: { id: row.id }, data: { reviewStatus: "REVIEWED", reviewedBy: reviewer.trim(), reviewedAt: now } });
    },

    async retire(key: string, version: number) {
      const row = await prisma.educationModule.findUnique({ where: { key_version: { key, version } } });
      if (!row) throw notFound("EDUCATION_MODULE_NOT_FOUND", "Modul tidak ditemukan.");
      return prisma.educationModule.update({ where: { id: row.id }, data: { reviewStatus: "RETIRED" } });
    },
  };
}

export const educationService = createEducationService({ includeDrafts: () => env.EDUCATION_INCLUDE_DRAFTS });
