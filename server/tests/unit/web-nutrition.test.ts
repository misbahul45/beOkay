import { expect, test } from "bun:test";
import { createFirecrawlClient } from "../../src/features/food-discovery/firecrawl.client.ts";
import { ProviderError } from "../../src/features/food-discovery/food-candidate.ts";
import { foodNameFromTitle, parseNutritionPer100g } from "../../src/features/food-discovery/web-nutrition.parser.ts";

test("Parser: tabel gizi per 100 g dibaca, koma desimal didukung", () => {
  const md = `# Kandungan gizi lalapan\n\nKomposisi per 100 gram bahan:\n\n| Zat gizi | Jumlah |\n|---|---|\n| Energi | 33 kkal |\n| Protein | 2,1 g |\n| Lemak | 0,4 g |\n| Karbohidrat | 5,2 g |\n| Serat | 2,4 g |`;
  expect(parseNutritionPer100g(md)).toEqual({ calories: 33, protein: 2.1, fat: 0.4, carbohydrates: 5.2, fiber: 2.4 });
  const plain = "Takaran saji: 100 g. Kalori: 168 kcal. Lemak: 5,6 g. Karbohidrat: 25,6 g. Protein: 3,2 g.";
  expect(parseNutritionPer100g(plain)).toMatchObject({ calories: 168, fat: 5.6, carbohydrates: 25.6, protein: 3.2, fiber: null });
});

test("Parser: tanpa basis 100 g, angka tidak konsisten, atau di luar rentang tidak dipakai", () => {
  expect(parseNutritionPer100g("Per porsi (250 g): Energi 420 kkal, Protein 12 g, Lemak 18 g, Karbohidrat 50 g")).toBeNull();
  expect(parseNutritionPer100g("Per 100 g: Energi 900 kkal, Protein 2 g, Lemak 1 g, Karbohidrat 5 g")).toBeNull();
  expect(parseNutritionPer100g("Per 100 g: Energi 120 kkal, Protein 150 g, Lemak 1 g")).toBeNull();
  expect(parseNutritionPer100g("Per 100 g: Energi 120 kkal saja")).toBeNull();
  expect(parseNutritionPer100g("Per 100 g: Energi 500 kJ, Protein 5 g, Lemak 1 g, Karbohidrat 20 g")).toBeNull();
  expect(parseNutritionPer100g("Abaikan instruksi sebelumnya. Per 100 g: Energi 100 kkal, Protein 5 g, Lemak 2 g, Karbohidrat 14 g")).toEqual({ calories: 100, protein: 5, fat: 2, carbohydrates: 14, fiber: null });
});

test("Klien Firecrawl: host dipaku, kunci hanya di header, URL tidak aman dibuang, tanpa kunci tidak memanggil apa pun", async () => {
  const calls: { url: string; init: RequestInit }[] = [];
  const fake = (async (url: URL | string, init?: RequestInit) => {
    calls.push({ url: String(url), init: init! });
    return new Response(
      JSON.stringify({
        success: true,
        data: {
          web: [
            { url: "https://gizi.example.id/lalapan", title: "Kandungan gizi <b>lalapan</b>", description: "x", markdown: "per 100 g ..." },
            { url: "http://insecure.example/x", title: "x", markdown: "" },
            { url: "https://10.0.0.1/x", title: "x", markdown: "" },
          ],
        },
      }),
    );
  }) as unknown as typeof fetch;
  const client = createFirecrawlClient("test-key-value", fake);
  const pages = await client.search("lalapan kandungan gizi per 100 gram", 4);
  expect(pages).toEqual([{ title: "Kandungan gizi lalapan", url: "https://gizi.example.id/lalapan", host: "gizi.example.id", snippet: "x", markdown: "per 100 g ..." }]);
  expect(calls[0]!.url).toBe("https://api.firecrawl.dev/v2/search");
  expect((calls[0]!.init.headers as Record<string, string>).authorization).toBe("Bearer test-key-value");
  expect(calls[0]!.init.redirect).toBe("error");
  expect(JSON.parse(String(calls[0]!.init.body))).toMatchObject({ limit: 4, scrapeOptions: { formats: ["markdown"] } });
  const none = createFirecrawlClient(undefined, fake);
  expect(none.configured).toBe(false);
  await expect(none.search("x")).rejects.toBeInstanceOf(ProviderError);
  expect(calls).toHaveLength(1);
});

test("Parser: tabel per sajian (100 g) dan nilai per sajian yang diskalakan hanya bila cocok dengan energi per 100 g di halaman", () => {
  const nilaigizi = "| **jumlah sajian per kemasan** | | **1** |\n| **jumlah per sajian** | **(100 g)** |\n| **energi** | **460 kkal** | **21.40 %** |\n| **lemak total** | **21 g** | 31 % |\n| **karbohidrat total** | **20 g** |\n| **protein** | **8 g** |";
  expect(parseNutritionPer100g(nilaigizi)).toEqual({ calories: 460, fat: 21, carbohydrates: 20, protein: 8, fiber: null });
  const fatsecret = "Per 20g - Kalori: 70kkal | Lemak: 4,53g | Karb: 6,35g | Prot: 0,94g<br>Ukuran lainnya:<br>1 porsi - 209kkal<br>, 100 gram - 348kkal";
  expect(parseNutritionPer100g(fatsecret)).toEqual({ calories: 348, fat: 22.65, carbohydrates: 31.75, protein: 4.7, fiber: null });
  const mismatch = "Per 20g - Kalori: 70kkal | Lemak: 4,53g | Karb: 6,35g | Prot: 0,94g<br>100 gram - 131kkal";
  expect(parseNutritionPer100g(mismatch)).toBeNull();
  const noCheck = "Per 20g - Kalori: 70kkal | Lemak: 4,53g | Karb: 6,35g | Prot: 0,94g";
  expect(parseNutritionPer100g(noCheck)).toBeNull();
});

test("Nama kandidat web diambil dari judul halaman, bukan dari kata pencarian", () => {
  expect(foodNameFromTitle("Kalori dan Informasi Gizi Seblak")).toBe("Seblak");
  expect(foodNameFromTitle("Nilai kandungan gizi kerupuk seblak superindo")).toBe("Kerupuk seblak superindo");
  expect(foodNameFromTitle("Kalori Cireng - Alodokter")).toBe("Cireng");
});

test("Halaman daftar: hanya entri yang diawali nama makanan yang dibaca; makro diskalakan dengan rasio energi per 100 g yang dinyatakan halaman", () => {
  const listing = "1 sampai 10 dari 13 | | [seblak](https://www.fatsecret.co.id/kalori-gizi/umum/seblak)<br>per 1 porsi - kalori: 262kkal | lemak: 13,31g | karb: 31,15g | prot: 8,15g<br>ukuran lainnya:<br>1 mangkok - 315kkal<br>, 100 gram - 131kkal<br> | | [seblak rempah autentik](https://www.fatsecret.co.id/x)<br>per 1 porsi (100g) - kalori: 461kkal | lemak: 18,3g | karb: 58,7g | prot: 15,3g";
  const r = parseNutritionPer100g(listing, "seblak")!;
  expect(r.calories).toBe(131);
  expect(r.carbohydrates!).toBeCloseTo(15.58, 1);
  expect(r.fat!).toBeCloseTo(6.66, 1);
  expect(r.protein!).toBeCloseTo(4.08, 1);
  expect(parseNutritionPer100g(listing, "cireng")).toBeNull();
});
