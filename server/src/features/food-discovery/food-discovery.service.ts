import { env } from "../../config/env.ts";
import { badRequest } from "../../shared/errors/app-error.ts";
import { AppError } from "../../shared/errors/app-error.ts";
import { consentService } from "../consent/consent.service.ts";
import { nutritionService } from "../nutrition/nutrition.service.ts";
import { checkFood, type PreferenceCheck } from "../food-preferences/food-preferences.model.ts";
import { foodPreferencesService } from "../food-preferences/food-preferences.service.ts";
import { validGtin } from "./barcode.ts";
import { ProviderError, type FoodCandidate } from "./food-candidate.ts";
import { createOffClient } from "./off.client.ts";
import { createUsdaClient } from "./usda.client.ts";
import { createWebSearchClient } from "./web-search.client.ts";
import { referenceService } from "../food-reference/reference.service.ts";
import { rateWindow } from "../../shared/http/rate-window.ts";
import { featureFlags } from "../feature-flags/feature-flags.service.ts";

type Off = ReturnType<typeof createOffClient>;
type Usda = ReturnType<typeof createUsdaClient>;
type Web = ReturnType<typeof createWebSearchClient>;

/** Batas pemanggilan ke luar per pengguna: 20 per 10 menit. */
const WINDOW_MS = 10 * 60_000;
const MAX_CALLS = 20;

type Reference = { search(q: string, limit?: number): Promise<{ status: "OK" | "LEXICAL_ONLY"; items: any[] }> };

export function createFoodDiscovery(deps: { off: Off; usda: Usda; web?: Web; reference?: Reference; now?: () => number }) {
  const calls = rateWindow(WINDOW_MS, MAX_CALLS);
  const now = deps.now ?? Date.now;
  function allow(userId: string) {
    const t = now();
    if (calls.full(userId, t)) throw new AppError(429, "EXTERNAL_LOOKUP_RATE_LIMITED", "Terlalu sering mencari di sumber luar. Coba lagi beberapa menit lagi.");
    calls.record(userId, t);
  }

  return {
    /**
     * Lokal dahulu. Sumber luar dipanggil hanya bila pengguna memintanya eksplisit (`external`),
     * karena teks pencarian dikirim ke pihak ketiga. Kegagalan penyedia tidak menggagalkan hasil lokal.
     */
    async discover(userId: string, q: string, external: boolean, opts: { hideExcluded?: boolean } = {}) {
      const local = await nutritionService.searchFoods(userId, q); // memeriksa consent
      const prefs = await foodPreferencesService.activeFor(userId);
      // Referensi TKPI (lokal, di database sendiri; tidak ada teks pencarian yang dikirim ke pihak ketiga selain embedding).
      const ref = deps.reference ? await deps.reference.search(q, 8).catch(() => ({ status: "UNAVAILABLE" as const, items: [] as any[] })) : { status: "NOT_CONFIGURED" as const, items: [] as any[] };
      // Setiap hasil diberi pengecekan preferensi/alergi (berdasarkan nama). Disembunyikan hanya bila diminta.
      const annotate = <T extends { name: string; brand?: string | null }>(items: T[]): (T & { preferenceCheck: PreferenceCheck })[] => {
        const out = items.map((i) => ({ ...i, preferenceCheck: checkFood(i.name, prefs, i.brand) }));
        return opts.hideExcluded ? out.filter((i) => i.preferenceCheck.status !== "EXCLUDED") : out;
      };
      const reference = { status: ref.status, items: annotate(ref.items as any[]) };
      if (!external) return { local: annotate(local.items as any[]), reference, external: { status: "NOT_REQUESTED" as const, providers: [], items: [] as (FoodCandidate & { preferenceCheck: PreferenceCheck })[] } };
      if (!(await featureFlags.isEnabled("web_discovery"))) return { local: annotate(local.items as any[]), reference, external: { status: "DISABLED" as const, providers: [], items: [] as (FoodCandidate & { preferenceCheck: PreferenceCheck })[] } };
      allow(userId);
      const providers = [
        { name: "Open Food Facts", run: () => deps.off.search(q) },
        { name: "USDA FoodData Central", run: () => deps.usda.search(q) },
      ];
      const settled = await Promise.allSettled(providers.map((p) => p.run()));
      const report = settled.map((r, i) => ({
        name: providers[i]!.name,
        status: r.status === "fulfilled" ? ("OK" as const) : ("UNAVAILABLE" as const),
        code: r.status === "rejected" && r.reason instanceof ProviderError ? r.reason.code : undefined,
      }));
      const items = settled.flatMap((r) => (r.status === "fulfilled" ? r.value : []));
      const ok = report.filter((r) => r.status === "OK").length;
      return {
        local: annotate(local.items as any[]),
        reference,
        external: { status: ok === report.length ? ("OK" as const) : ok === 0 ? ("UNAVAILABLE" as const) : ("PARTIAL" as const), providers: report, items: annotate(items) },
      };
    },

    /**
     * Pencarian web hanya atas permintaan eksplisit, memakai pembatas laju yang sama dengan sumber luar.
     * Hasil adalah tautan + cuplikan untuk dibaca pengguna; tidak pernah menjadi data gizi.
     */
    async web(userId: string, q: string) {
      await consentService.requireConsent(userId, "health_data_processing");
      if (!deps.web) return { status: "NOT_CONFIGURED" as const, items: [] };
      if (!deps.web.configured) return { status: "NOT_CONFIGURED" as const, items: [] };
      allow(userId);
      try {
        return { status: "OK" as const, items: await deps.web.search(q) };
      } catch (e) {
        if (e instanceof ProviderError) return { status: "UNAVAILABLE" as const, items: [], code: e.code };
        throw e;
      }
    },

    async barcode(userId: string, code: string) {
      await consentService.requireConsent(userId, "health_data_processing");
      if (!validGtin(code)) throw badRequest("INVALID_BARCODE", "Kode batang tidak valid.");
      allow(userId);
      try {
        const candidate = await deps.off.byBarcode(code);
        return { status: candidate ? ("FOUND" as const) : ("NOT_FOUND" as const), candidate };
      } catch (e) {
        if (e instanceof ProviderError) return { status: "UNAVAILABLE" as const, candidate: null, code: e.code };
        throw e;
      }
    },
  };
}

export const foodDiscoveryService = createFoodDiscovery({ off: createOffClient(), usda: createUsdaClient(env.USDA_API_KEY), web: createWebSearchClient(env.BRAVE_API_KEY), reference: referenceService });
