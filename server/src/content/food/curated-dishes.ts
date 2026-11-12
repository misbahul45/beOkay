export type CuratedDish = {
  code: string;
  name: string;
  serving: { min: number; typical: number; max: number };
  ingredients: [tkpiCode: string, grams: number][];
  addedWaterG?: number;
  note?: string;
};

export const CURATED_VERSION = "curated-dishes-v1";
export const CURATED_SOURCE = "Kurasi beOkay (resep standar dari bahan TKPI)";

const BUMBU_DASAR: [string, number][] = [["NR007", 10], ["NR008", 5]];

export const CURATED_DISHES: CuratedDish[] = [
  { code: "CUR-001", name: "Nasi goreng telur", serving: { min: 200, typical: 290, max: 400 }, ingredients: [["AP001", 200], ["HR002", 50], ["KR012", 10], ["NP005", 10], ...BUMBU_DASAR, ["NR014", 5]] },
  { code: "CUR-002", name: "Nasi goreng ayam", serving: { min: 200, typical: 305, max: 420 }, ingredients: [["AP001", 200], ["FR005", 40], ["HR002", 25], ["KR012", 10], ["NP005", 10], ...BUMBU_DASAR, ["NR014", 5]] },
  { code: "CUR-003", name: "Mie goreng telur", serving: { min: 200, typical: 315, max: 400 }, ingredients: [["AP021", 200], ["HR002", 25], ["DR044", 30], ["DR141", 20], ["KR012", 10], ["NP005", 15], ...BUMBU_DASAR] },
  { code: "CUR-004", name: "Bihun goreng", serving: { min: 150, typical: 265, max: 350 }, ingredients: [["AP006", 60], ["HR002", 25], ["DR044", 30], ["KR012", 10], ["NP005", 10], ...BUMBU_DASAR], addedWaterG: 120, note: "Air rendaman yang terserap bihun dihitung 120 g." },
  { code: "CUR-005", name: "Mie rebus telur", serving: { min: 250, typical: 386, max: 500 }, ingredients: [["AP021", 150], ["HR002", 25], ["DR141", 20], ["KR012", 3], ["NR008", 3], ["NP005", 5]], addedWaterG: 180 },
  { code: "CUR-006", name: "Nasi uduk", serving: { min: 150, typical: 220, max: 300 }, ingredients: [["AP001", 200], ["KP004", 20]] },
  { code: "CUR-007", name: "Nasi kuning", serving: { min: 150, typical: 217, max: 300 }, ingredients: [["AP001", 200], ["KP004", 15], ["NR022", 2]] },
  { code: "CUR-008", name: "Lontong sayur", serving: { min: 300, typical: 466, max: 550 }, ingredients: [["AP001", 150], ["DR123", 60], ["DR097", 20], ["CP062", 20], ["HR002", 25], ["KP004", 30], ["NR007", 5], ["NR008", 3]], addedWaterG: 153, note: "Lontong dihitung sebagai nasi (TKPI tidak memuat lontong)." },
  { code: "CUR-009", name: "Ketoprak", serving: { min: 250, typical: 321, max: 400 }, ingredients: [["CP062", 60], ["AP001", 100], ["AP006", 15], ["DR148", 30], ["CP012", 30], ["NP005", 10], ["NR008", 3], ["NR015", 3], ["BP045", 5]], addedWaterG: 65, note: "Lontong dihitung sebagai nasi; air rendaman bihun dan air bumbu kacang dihitung 65 g." },
  { code: "CUR-010", name: "Pecel sayur bumbu kacang", serving: { min: 150, typical: 252, max: 300 }, ingredients: [["DR100", 40], ["DR008", 30], ["DR148", 30], ["DR097", 30], ["DR044", 20], ["CP012", 35], ["MP005", 8], ["NR014", 3], ["NR008", 3]], addedWaterG: 23 },
  { code: "CUR-011", name: "Nasi pecel", serving: { min: 250, typical: 325, max: 420 }, ingredients: [["AP001", 150], ["DR100", 30], ["DR008", 20], ["DR148", 20], ["DR097", 20], ["CP012", 25], ["MP005", 6], ["NR014", 2], ["NR008", 2]], addedWaterG: 50 },
  { code: "CUR-012", name: "Sayur lodeh", serving: { min: 150, typical: 328, max: 400 }, ingredients: [["DR123", 50], ["DR097", 30], ["DR154", 30], ["CP077", 20], ["KP004", 40], ["NR007", 5], ["NR008", 3]], addedWaterG: 150 },
  { code: "CUR-013", name: "Tumis kangkung", serving: { min: 100, typical: 175, max: 220 }, ingredients: [["DR100", 150], ["KR012", 10], ["NR008", 5], ["NR007", 5], ["NR015", 3], ["NP011", 2]] },
  { code: "CUR-014", name: "Tumis buncis wortel", serving: { min: 100, typical: 168, max: 220 }, ingredients: [["DP003", 120], ["DR166", 30], ["KR012", 8], ["NR008", 5], ["NR007", 5]] },
  { code: "CUR-015", name: "Tumis tauge", serving: { min: 100, typical: 134, max: 200 }, ingredients: [["DR148", 120], ["KR012", 8], ["NR008", 3], ["NR007", 3]] },
  { code: "CUR-016", name: "Cah sawi", serving: { min: 100, typical: 132, max: 200 }, ingredients: [["DR141", 120], ["KR012", 8], ["NR008", 4]] },
  { code: "CUR-017", name: "Urap sayur", serving: { min: 100, typical: 168, max: 220 }, ingredients: [["DR100", 40], ["DR008", 30], ["DR148", 30], ["DR097", 30], ["KR002", 30], ["NR014", 3], ["NR008", 2], ["MP005", 3]] },
  { code: "CUR-018", name: "Sayur bening bayam", serving: { min: 150, typical: 265, max: 330 }, ingredients: [["DR008", 80], ["AR015", 30], ["NR007", 5]], addedWaterG: 150 },
  { code: "CUR-019", name: "Orek tempe", serving: { min: 50, typical: 113, max: 150 }, ingredients: [["CP076", 80], ["NP005", 15], ["MP005", 5], ["NR007", 5], ["NR008", 3], ["NR014", 5]] },
  { code: "CUR-020", name: "Tempe mendoan", serving: { min: 50, typical: 139, max: 200 }, ingredients: [["CP077", 60], ["AP025", 20], ["KR012", 12], ["NR008", 2]], addedWaterG: 25, note: "Minyak yang terserap diperkirakan 12 g per porsi." },
  { code: "CUR-021", name: "Tahu isi", serving: { min: 60, typical: 152, max: 200 }, ingredients: [["CP062", 60], ["DR148", 20], ["DR166", 15], ["AP025", 20], ["KR012", 12]], addedWaterG: 25, note: "Minyak yang terserap diperkirakan 12 g per porsi." },
  { code: "CUR-022", name: "Perkedel kentang", serving: { min: 50, typical: 108, max: 150 }, ingredients: [["BR013", 80], ["HR002", 15], ["KR012", 8], ["NR007", 3], ["NR008", 2]] },
  { code: "CUR-023", name: "Telur balado", serving: { min: 60, typical: 95, max: 140 }, ingredients: [["HR002", 55], ["NR014", 15], ["NR007", 10], ["NR008", 3], ["MP007", 2], ["KR012", 10]] },
  { code: "CUR-024", name: "Ayam bakar kecap", serving: { min: 80, typical: 133, max: 200 }, ingredients: [["FR005", 100], ["NP005", 15], ["MP005", 5], ["KR012", 5], ["NR007", 5], ["NR008", 3]] },
  { code: "CUR-025", name: "Opor ayam", serving: { min: 150, typical: 247, max: 330 }, ingredients: [["FR005", 80], ["KP004", 50], ["NR007", 8], ["NR008", 4], ["NR019", 3], ["NR022", 2]], addedWaterG: 100 },
  { code: "CUR-026", name: "Gulai ayam", serving: { min: 150, typical: 251, max: 330 }, ingredients: [["FR005", 80], ["KP004", 60], ["NR022", 2], ["NR007", 6], ["NR008", 3]], addedWaterG: 100 },
  { code: "CUR-027", name: "Semur daging sapi", serving: { min: 120, typical: 237, max: 300 }, ingredients: [["FR025", 80], ["BR013", 40], ["NP005", 20], ["NR007", 8], ["NR008", 4], ["KR012", 5]], addedWaterG: 80 },
  { code: "CUR-028", name: "Rawon daging sapi", serving: { min: 250, typical: 341, max: 450 }, ingredients: [["FR025", 60], ["NR019", 3], ["NR007", 5], ["NR008", 3], ["KR012", 5], ["DR148", 15]], addedWaterG: 250, note: "Kluwek tidak ada di TKPI dan tidak dihitung." },
  { code: "CUR-029", name: "Sate ayam bumbu kacang", serving: { min: 80, typical: 140, max: 220 }, ingredients: [["FR005", 80], ["CP012", 25], ["NP005", 10], ["MP005", 5], ["KR012", 3], ["NR008", 2]], addedWaterG: 15, note: "Satu porsi sekitar 8–10 tusuk dengan bumbu kacang; tanpa lontong." },
  { code: "CUR-030", name: "Soto ayam", serving: { min: 250, typical: 383, max: 500 }, ingredients: [["FR005", 40], ["DR148", 20], ["AP006", 10], ["HR002", 25], ["KR012", 5], ["NR022", 2], ["NR008", 3], ["NR007", 5], ["DR044", 15]], addedWaterG: 258, note: "Tanpa nasi; kuah dan air rendaman bihun dihitung 258 g." },
  { code: "CUR-031", name: "Sup ayam sayur", serving: { min: 200, typical: 326, max: 450 }, ingredients: [["FR005", 50], ["BR013", 40], ["DR166", 30], ["DR044", 30], ["NR008", 3], ["NR007", 3]], addedWaterG: 170 },
  { code: "CUR-032", name: "Bubur ayam", serving: { min: 250, typical: 290, max: 400 }, ingredients: [["AP001", 100], ["FR005", 30], ["NP005", 5], ["BP045", 5]], addedWaterG: 150, note: "Bubur dihitung dari nasi ditambah air 150 g." },
  { code: "CUR-033", name: "Ikan tongkol goreng", serving: { min: 60, typical: 114, max: 150 }, ingredients: [["GR070", 100], ["KR012", 10], ["NR022", 2], ["NR008", 2]], note: "Minyak yang terserap diperkirakan 10 g per porsi." },
  { code: "CUR-034", name: "Ikan bandeng bakar", serving: { min: 80, typical: 118, max: 180 }, ingredients: [["GR007", 100], ["NP005", 10], ["KR012", 5], ["NR008", 3]] },
  { code: "CUR-035", name: "Udang balado", serving: { min: 80, typical: 125, max: 180 }, ingredients: [["GR084", 80], ["NR014", 20], ["NR007", 10], ["NR008", 3], ["KR012", 10], ["MP007", 2]] },
  { code: "CUR-036", name: "Sambal tomat", serving: { min: 10, typical: 20, max: 40 }, ingredients: [["NR014", 40], ["NR015", 10], ["NR007", 15], ["NR008", 5], ["DR161", 20], ["KR012", 10], ["MP007", 2], ["NP011", 3]], note: "Resep untuk satu cobek (105 g); porsi umum satu sendok makan." },
  { code: "CUR-037", name: "Martabak telur", serving: { min: 80, typical: 145, max: 250 }, ingredients: [["AP025", 50], ["HR002", 50], ["FR025", 20], ["NR007", 10], ["KR012", 15]] },
  { code: "CUR-038", name: "Pisang goreng", serving: { min: 60, typical: 133, max: 200 }, ingredients: [["ER081", 80], ["AP025", 20], ["KR012", 10], ["MP007", 3]], addedWaterG: 20, note: "Minyak yang terserap diperkirakan 10 g per buah." },
  { code: "CUR-039", name: "Singkong goreng", serving: { min: 60, typical: 112, max: 200 }, ingredients: [["BR016", 100], ["KR012", 10], ["NR008", 2]] },
  { code: "CUR-040", name: "Kolak pisang", serving: { min: 150, typical: 245, max: 300 }, ingredients: [["ER081", 80], ["MP005", 25], ["KP004", 40]], addedWaterG: 100 },
  { code: "CUR-041", name: "Bubur kacang hijau", serving: { min: 150, typical: 225, max: 300 }, ingredients: [["CP005", 80], ["MP005", 20], ["KP004", 25]], addedWaterG: 100 },
  { code: "CUR-042", name: "Teh manis", serving: { min: 200, typical: 270, max: 350 }, ingredients: [["MP007", 20]], addedWaterG: 250, note: "Teh tidak dihitung; nilai berasal dari gula 20 g (sekitar dua sendok makan)." },
  { code: "CUR-043", name: "Kopi susu kental manis", serving: { min: 150, typical: 180, max: 250 }, ingredients: [["JP007", 30]], addedWaterG: 150, note: "Kopi tidak dihitung; nilai berasal dari susu kental manis 30 g." },
  { code: "CUR-044", name: "Gado-gado lontong", serving: { min: 300, typical: 370, max: 450 }, ingredients: [["AP001", 120], ["DR100", 30], ["DR148", 30], ["DR097", 30], ["DR044", 30], ["BR013", 30], ["CP062", 25], ["HR002", 25], ["CP012", 35], ["MP005", 8], ["BP045", 5]], addedWaterG: 2, note: "Lontong dihitung sebagai nasi." },
  { code: "CUR-045", name: "Nasi campur ayam sayur", serving: { min: 300, typical: 380, max: 500 }, ingredients: [["AP001", 200], ["FR005", 60], ["DR100", 40], ["CP076", 30], ["KR012", 10], ["NR014", 10], ["NR007", 10], ["NR008", 5], ["DR161", 15]] },
];

export const TOP_QUERIES = [
  "nasi goreng", "mie goreng", "nasi uduk", "lontong", "soto ayam", "sate ayam", "bakso", "gado-gado", "pecel", "rendang",
  "tempe goreng", "tahu goreng", "ayam goreng", "opor ayam", "nasi kuning", "sayur asem", "sambal", "pisang goreng", "bubur ayam", "martabak",
];
