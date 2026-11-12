import { z } from "zod";
import { env } from "../../config/env.ts";
import { logEvent } from "../../shared/http/logger.ts";
import { AppError } from "../../shared/errors/app-error.ts";
import { consentService } from "../consent/consent.service.ts";
import { buildCandidate, ProviderError, type FoodCandidate } from "../food-discovery/food-candidate.ts";
import { nutritionService } from "../nutrition/nutrition.service.ts";
import { referenceService } from "../food-reference/reference.service.ts";
import { type ImageMime, toDataUrl } from "./image.ts";
import { parseLabel } from "./label-parser.ts";
import { createMistralClient } from "./mistral.client.ts";
import { rateWindow } from "../../shared/http/rate-window.ts";

type Mistral = ReturnType<typeof createMistralClient>;
type Food = { id: string; name: string; [k: string]: unknown };
type Search = (userId: string, q: string) => Promise<{ items: Food[] }>;
/** Pencarian gizi dari referensi (RAG: kata + makna) tanpa data pengguna. */
type Reference = (q: string) => Promise<{ items: unknown[] }>;

const WINDOW_MS = 10 * 60_000;
const MAX_CALLS = 10;

/** Keluaran model hanya dipercaya setelah lolos skema ini; teks bebas lain dibuang. */
export const photoOutput = z.object({
  isFood: z.boolean(),
  items: z
    .array(z.object({ name: z.string().trim().min(2).max(60), confidence: z.enum(["high", "medium", "low"]) }))
    .max(6)
    .default([]),
});

const NAME_STOP = new Set(["dan", "dengan", "atau", "yang", "masakan", "segar"]);
const words = (s: string) => s.toLowerCase().normalize("NFKD").replace(/\p{M}/gu, "").replace(/[^a-z0-9\s]/g, " ").split(/\s+/).filter((w) => w.length >= 3 && !NAME_STOP.has(w));
const near = (a: string, b: string) => {
  if (a === b) return true;
  if (a.length < 5 || b.length < 5 || a[0] !== b[0] || Math.abs(a.length - b.length) > 1) return false; // huruf pertama harus sama: sambal ≠ jambal
  // jarak edit ≤ 1 (salah ketik / ejaan: krupuk ↔ kerupuk)
  let i = 0, j = 0, edits = 0;
  while (i < a.length && j < b.length) {
    if (a[i] === b[j]) { i++; j++; continue; }
    if (++edits > 1) return false;
    if (a.length > b.length) i++;
    else if (a.length < b.length) j++;
    else { i++; j++; }
  }
  return edits + (a.length - i) + (b.length - j) <= 1;
};
/**
 * Padanan referensi hanya dipakai bila SETIAP kata penting pada nama dari foto ada pada nama referensi.
 * Pencarian makna (embedding) selalu mengembalikan tetangga terdekat, termasuk yang salah ("nasi goreng" → "gendar goreng");
 * menampilkan gizi makanan yang keliru lebih buruk daripada mengaku belum ketemu.
 */
export function referenceCovers(photoName: string, referenceName: string): boolean {
  const need = words(photoName);
  if (need.length === 0) return false;
  const have = words(referenceName);
  return need.every((n) => have.some((h) => near(n, h)));
}

const sanitize = (s: string) => s.replace(/[\u0000-\u001f\u007f<>]/g, " ").replace(/\s+/g, " ").trim();

export function createFoodVision(deps: { mistral: Mistral; search?: Search; reference?: Reference; now?: () => number }) {
  const calls = rateWindow(WINDOW_MS, MAX_CALLS);
  const now = deps.now ?? Date.now;
  const search: Search = deps.search ?? ((u, q) => nutritionService.searchFoods(u, q));
  const reference: Reference = deps.reference ?? ((q) => referenceService.search(q, 2));

  function allow(userId: string) {
    const t = now();
    if (calls.full(userId, t)) throw new AppError(429, "IMAGE_SCAN_RATE_LIMITED", "Terlalu sering memindai gambar. Coba lagi beberapa menit lagi.");
    calls.record(userId, t);
  }

  async function guarded<T, F>(userId: string, run: () => Promise<T>, fallback: (code: string) => F): Promise<T | F> {
    await consentService.requireConsent(userId, "health_data_processing");
    if (!deps.mistral.configured) return fallback("PROVIDER_NOT_CONFIGURED");
    allow(userId);
    try {
      return await run();
    } catch (e) {
      if (e instanceof ProviderError) return fallback(e.code);
      throw e;
    }
  }

  return {
    /** Foto label kemasan → teks (OCR) → angka lewat parser deterministik. Pengguna wajib memeriksa hasilnya. */
    scanLabel(userId: string, image: { bytes: Uint8Array; mime: ImageMime }) {
      return guarded(
        userId,
        async () => {
          const markdown = await deps.mistral.ocr(toDataUrl(image.bytes, image.mime));
          const parsed = parseLabel(markdown);
          const known = Object.values(parsed.printed).filter((v) => v !== null).length;
          // Hanya metadata (tanpa isi gambar atau teks) untuk menelusuri kegagalan baca.
          logEvent("info", "food_scan_label", { imageBytes: image.bytes.length, mime: image.mime, ocrChars: markdown.length, valuesRead: known, basis: parsed.basis, flags: parsed.flags.join(",") });
          if (known === 0) return { status: "NO_NUTRITION" as const, candidate: null, label: parsed, rawText: markdown.slice(0, 4000) };
          const candidate: FoodCandidate = buildCandidate(
            { externalId: "label", name: "Produk dari label", brand: null, source: "Label kemasan (OCR)", sourceVersion: "ocr" },
            parsed.per100g,
          );
          return { status: "READ" as const, candidate, label: parsed, rawText: markdown.slice(0, 4000) };
        },
        (code) => ({ status: "UNAVAILABLE" as const, code, candidate: null, label: null, rawText: "" }),
      );
    },

    /** Foto makanan → hanya nama kandidat + padanan di katalog. Kalori dan porsi tidak diestimasi model. */
    identifyPhoto(userId: string, image: { bytes: Uint8Array; mime: ImageMime }) {
      return guarded(
        userId,
        async () => {
          const raw = await deps.mistral.identify(toDataUrl(image.bytes, image.mime));
          const parsed = photoOutput.safeParse(raw);
          if (!parsed.success) throw new ProviderError("PROVIDER_BAD_RESPONSE", "Balasan model tidak sesuai.");
          if (!parsed.data.isFood || parsed.data.items.length === 0) return { status: "NOT_FOOD" as const, items: [] };
          const items = [];
          for (const it of parsed.data.items) {
            const name = sanitize(it.name);
            if (name.length < 2) continue;
            const tokens = [name, ...name.split(" ").filter((t) => t.length >= 3).sort((a, b) => b.length - a.length)];
            let matches: Food[] = [];
            for (const t of tokens) {
              matches = (await search(userId, t)).items.slice(0, 3);
              if (matches.length) break;
            }
            // Gizi dari referensi (hybrid kata + makna). Gagal/kosong tidak mengganggu hasil foto; nilai tidak pernah ditebak dari gambar.
            let ref: unknown[] = [];
            try {
              ref = (await reference(name)).items.filter((x) => referenceCovers(name, String((x as { name?: unknown }).name ?? ""))).slice(0, 2);
            } catch {
              ref = [];
            }
            items.push({ name, confidence: it.confidence, matches, reference: ref });
          }
          return { status: items.length ? ("IDENTIFIED" as const) : ("NOT_FOOD" as const), items };
        },
        (code) => ({ status: "UNAVAILABLE" as const, code, items: [] }),
      );
    },
  };
}

export const foodVisionService = createFoodVision({
  mistral: createMistralClient({ apiKey: env.MISTRAL_API_KEY, ocrModel: env.MISTRAL_OCR_MODEL, visionModel: env.MISTRAL_VISION_MODEL }),
});
