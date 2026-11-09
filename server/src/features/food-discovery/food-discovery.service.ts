import { env } from "../../config/env.ts";
import { badRequest } from "../../shared/errors/app-error.ts";
import { AppError } from "../../shared/errors/app-error.ts";
import { consentService } from "../consent/consent.service.ts";
import { nutritionService } from "../nutrition/nutrition.service.ts";
import { validGtin } from "./barcode.ts";
import { ProviderError, type FoodCandidate } from "./food-candidate.ts";
import { createOffClient } from "./off.client.ts";
import { createUsdaClient } from "./usda.client.ts";

type Off = ReturnType<typeof createOffClient>;
type Usda = ReturnType<typeof createUsdaClient>;

/** Batas pemanggilan ke luar per pengguna: 20 per 10 menit. */
const WINDOW_MS = 10 * 60_000;
const MAX_CALLS = 20;

export function createFoodDiscovery(deps: { off: Off; usda: Usda; now?: () => number }) {
  const calls = new Map<string, number[]>();
  const now = deps.now ?? Date.now;
  function allow(userId: string) {
    const t = now();
    const recent = (calls.get(userId) ?? []).filter((x) => t - x < WINDOW_MS);
    if (recent.length >= MAX_CALLS) {
      calls.set(userId, recent);
      throw new AppError(429, "EXTERNAL_LOOKUP_RATE_LIMITED", "Terlalu sering mencari di sumber luar. Coba lagi beberapa menit lagi.");
    }
    calls.set(userId, [...recent, t]);
  }

  return {
    /**
     * Lokal dahulu. Sumber luar dipanggil hanya bila pengguna memintanya eksplisit (`external`),
     * karena teks pencarian dikirim ke pihak ketiga. Kegagalan penyedia tidak menggagalkan hasil lokal.
     */
    async discover(userId: string, q: string, external: boolean) {
      const local = await nutritionService.searchFoods(userId, q); // memeriksa consent
      if (!external) return { local: local.items, external: { status: "NOT_REQUESTED" as const, providers: [], items: [] as FoodCandidate[] } };
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
        local: local.items,
        external: { status: ok === report.length ? ("OK" as const) : ok === 0 ? ("UNAVAILABLE" as const) : ("PARTIAL" as const), providers: report, items },
      };
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

export const foodDiscoveryService = createFoodDiscovery({ off: createOffClient(), usda: createUsdaClient(env.USDA_API_KEY) });
