export const SAFETY_POLICY_VERSION = "safety-policy-v2";

export type SafetyCode =
  | "SELF_HARM"
  | "URGENT_SYMPTOM"
  | "GLUCOSE_EXTREME"
  | "SYMPTOM_REVIEW"
  | "INJURY_OR_PAIN"
  | "INTENSITY_ESCALATION"
  | "MEDICATION_ADVICE"
  | "DIAGNOSIS_REQUEST"
  | "HEALTH_CLAIM_REQUEST"
  | "EXTREME_RESTRICTION";

export type ScreenDecision =
  | { decision: "ALLOWED" }
  | { decision: "BLOCKED" | "NEEDS_CLINICAL_REVIEW"; code: SafetyCode; message: string; urgent: boolean };

const URGENT_CODES: ReadonlySet<string> = new Set(["SELF_HARM", "URGENT_SYMPTOM", "GLUCOSE_EXTREME"]);
export const isUrgentSafetyCode = (code: string | null | undefined) => code != null && URGENT_CODES.has(code);

export const GLUCOSE_LIMITS = { mgdlLow: 70, mgdlHigh: 300, mmolLow: 3.9, mmolHigh: 16.7 } as const;

const ALIASES: Record<string, string> = {
  tdk: "tidak", gak: "tidak", ga: "tidak", gk: "tidak", nggak: "tidak", ngga: "tidak", enggak: "tidak", engga: "tidak", ndak: "tidak", nda: "tidak", kagak: "tidak",
  bgt: "banget", bngt: "banget", bener: "benar",
  sy: "saya", aq: "saya", aku: "saya", gw: "saya", gue: "saya", gua: "saya", ane: "saya",
  yg: "yang", dgn: "dengan", sdh: "sudah", udh: "sudah", udah: "sudah", krn: "karena", jg: "juga", trs: "terus", bkn: "bukan", aja: "saja", tp: "tapi",
  pengen: "ingin", pingin: "ingin", pengin: "ingin", kepengen: "ingin", kepingin: "ingin", mo: "mau",
  nafas: "napas", nafes: "napas", nfs: "napas", sesek: "sesak",
  pinsan: "pingsan", pingsn: "pingsan", pingsang: "pingsan", klenger: "semaput", kelenger: "semaput", kapiuhan: "semaput",
  lemes: "lemas", gemeteran: "gemetar", gemetaran: "gemetar", gemeter: "gemetar", tremor: "gemetar",
  keringet: "keringat", kringat: "keringat", kringet: "keringat",
  ngomong: "bicara", omongan: "bicara", ngomongnya: "bicara", bicaranya: "bicara",
  metformim: "metformin", metfomin: "metformin", metformine: "metformin", metformin500: "metformin",
  nurunin: "menurunkan", turunin: "menurunkan", turunkan: "menurunkan",
  dikurangin: "dikurangi", ditambahin: "ditambah", distop: "dihentikan", diberhentikan: "dihentikan",
  mumet: "pusing", ngelu: "pusing", lieur: "pusing", kliyengan: "pusing", kleyengan: "pusing", vertigo: "pusing",
  jempol: "jari",
};
const STEMS = new Set(["dada", "darah", "napas", "nafas", "gula", "kaki", "kepala", "obat", "insulin", "jantung", "badan", "perut", "mata", "pandangan", "wajah", "muka", "mulut", "tangan", "luka", "lutut", "punggung", "pinggang", "jari", "kuku", "suami", "istri", "anak", "ibu", "bapak"]);

function canonical(text: string): string {
  const base = text
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/\b([a-z]{3,})2(?![0-9])/g, "$1 $1")
    .replace(/[^a-z0-9.,/\s]/g, " ")
    .replace(/(?<![0-9])[.,]|[.,](?![0-9])/g, " ")
    .replace(/([a-z])\1{2,}/g, "$1")
    .replace(/\b(deg ?deg ?an|dag ?dig ?dug)\b/g, "berdebar");
  return base
    .split(/\s+/)
    .filter(Boolean)
    .map((tok) => {
      const alias = ALIASES[tok];
      if (alias) return alias;
      const m = tok.match(/^([a-z]+?)(ku|mu|nya)$/);
      if (m && STEMS.has(m[1]!)) return ALIASES[m[1]!] ?? m[1]!;
      return tok;
    })
    .join(" ");
}

const GLUCOSE_HEAD = /(?:gula darah|kadar gula|glukosa|\bgd[sp]?\b|\bgula\b(?! (?:pasir|aren|merah|batu|jawa|palem|tebu|kelapa|halus|cair|stevia|diet|rendah|tinggi|tambahan)))/g;
const NUMBER_TOKEN = /^(\d{1,3}(?:[.,]\d{1,2})?)(mg\/?dl|mg|mmol(?:\/l)?)?$/;
const NOT_GLUCOSE_UNIT = new Set(["g", "gr", "gram", "sdm", "sdt", "kg", "ml", "sendok", "kalori", "kkal", "kcal", "persen", "kali", "hari", "minggu", "menit", "jam", "tahun", "thn", "bulan", "potong", "butir", "biji", "porsi", "x", "piring", "gelas", "buah", "lembar", "mangkok", "mangkuk", "kotak", "bungkus", "langkah", "km", "tusuk", "cangkir"]);
const NOT_GLUCOSE_PREFIX = /^(jam|pukul|tanggal|tgl|nomor|no|naik|turun|selisih|beda|kurang|lebih|tambah|sekitar jam)$/;
const WINDOW = 6;

export function extremeGlucose(text: string): { value: number; unit: "mg/dL" | "mmol/L" } | null {
  const t = canonical(text);
  for (const m of t.matchAll(GLUCOSE_HEAD)) {
    const toks = t.slice(m.index! + m[0].length).trim().split(" ").slice(0, WINDOW);
    for (let i = 0; i < toks.length; i++) {
      const num = toks[i]!.match(NUMBER_TOKEN);
      if (!num) continue;
      const prev = toks[i - 1];
      const next = toks[i + 1];
      if (prev && NOT_GLUCOSE_PREFIX.test(prev)) continue;
      let unit = num[2] ?? null;
      if (!unit && next && /^(mg|mmol)/.test(next)) unit = next;
      if (!unit && next && NOT_GLUCOSE_UNIT.has(next)) continue;
      const value = Number(num[1]!.replace(",", "."));
      if (!Number.isFinite(value) || value <= 0) continue;
      const decimal = /[.,]/.test(num[1]!);
      const mmol = unit ? unit.startsWith("mmol") : decimal ? value < 35 : value < 20;
      if (mmol) return value < GLUCOSE_LIMITS.mmolLow || value >= GLUCOSE_LIMITS.mmolHigh ? { value, unit: "mmol/L" } : null;
      return value < GLUCOSE_LIMITS.mgdlLow || value >= GLUCOSE_LIMITS.mgdlHigh ? { value, unit: "mg/dL" } : null;
    }
  }
  return null;
}

const HYPO_SIGNS: RegExp[] = [/\bgemetar/, /\bkeringat/, /\bberdebar/, /\blemas/, /\bpusing/, /\blinglung/, /\bpandangan (kabur|gelap|berkunang)/, /\blapar (banget|sekali)/];
const hypoCluster = (t: string) => HYPO_SIGNS.filter((re) => re.test(t)).length >= 2;

const RAMADAN = /(ramadan|ramadhan|sahur|berbuka|buka puasa|puasa sunnah|senin kamis|puasa wajib)/;
const NUMBER_WORDS: Record<string, number> = { dua: 2, tiga: 3, empat: 4, lima: 5, enam: 6, tujuh: 7, seminggu: 7 };
function prolongedFast(t: string): boolean {
  if (RAMADAN.test(t)) return false;
  for (const m of t.matchAll(/(?:puasa|tidak makan|skip makan|mogok makan) (?:selama )?(\d+|dua|tiga|empat|lima|enam|tujuh|seminggu)(?: hari)?/g)) {
    const raw = m[1]!;
    const n = NUMBER_WORDS[raw] ?? Number(raw);
    if ((raw === "seminggu" || /hari/.test(m[0])) && n >= 2) return true;
  }
  return false;
}

type Rule = { code: SafetyCode; decision: "BLOCKED" | "NEEDS_CLINICAL_REVIEW"; test: (t: string, raw: string) => boolean; message: string };
const re = (pattern: RegExp) => (t: string) => pattern.test(t);

const RULES: Rule[] = [
  {
    code: "SELF_HARM",
    decision: "NEEDS_CLINICAL_REVIEW",
    test: re(/(bunuh diri|\bbundir\b|ingin mati|mau mati saja|lebih baik mati|mending mati|mengakhiri hidup|akhiri hidup|tidak (ingin|mau) hidup (lagi|lebih lama)|(capek|lelah) hidup(?! sehat)|menyakiti diri|melukai diri|nyakitin diri|sayat (tangan|nadi)|potong nadi|self harm|suicid|kill myself|end my life|want to die)/),
    message:
      "Terima kasih sudah bercerita. Kamu tidak harus menghadapinya sendirian. Jika kamu merasa tidak aman sekarang, segera hubungi layanan gawat darurat atau minta orang terdekat menemanimu. Bicara dengan tenaga kesehatan jiwa juga bisa membantu.",
  },
  {
    code: "URGENT_SYMPTOM",
    decision: "NEEDS_CLINICAL_REVIEW",
    test: (t) =>
      hypoCluster(t) ||
      /(pingsan|semaput|tidak sadarkan diri|hilang kesadaran|kehilangan kesadaran|tidak sadar diri|(jatuh|sampai|hampir|terus) tidak sadar|\bfaint|pass(ed)? out|unconscious)/.test(t) ||
      /(nyeri dada|sakit dada|dada (terasa |rasanya |seperti |kayak |kaya )?(sesak|nyeri|sakit|berat|tertekan|ditekan|ditindih|diremas)|chest (pain|hurts|tight))/.test(t) ||
      /(sesak napas|napas (sesak|tersengal|sengal|berat|pendek|cepat)|(susah|sulit|tidak bisa) (napas|bernapas)|napas bau (buah|aseton)|shortness of breath|short of breath|can t breathe|cannot breathe)/.test(t) ||
      /(\bkejang|seizure|convulsion)/.test(t) ||
      /(keringat dingin|gemetar hebat|cold sweat)/.test(t) ||
      /(linglung|(bicara|suara) (pelo|cadel|ngelantur|tidak jelas|kacau)|(wajah|muka|mulut|bibir) (mencong|miring|perot|turun sebelah)|\blumpuh|(lemah|mati rasa|kesemutan|tidak bisa digerakkan|kebas) (sebelah|separuh)|(sebelah|separuh) badan|serangan (jantung|stroke)|kena stroke)/.test(t) ||
      /(muntah (terus|berulang|tidak berhenti|muntah|sudah \d+ kali|lebih dari)|tidak bisa (makan dan minum|makan minum|minum sama sekali)|ketoasidosis|hipoglikemia|hiperglikemia|\bhipo\b|dehidrasi berat)/.test(t) ||
      /(pandangan (gelap|hilang) (mendadak|tiba tiba)|buta mendadak|tiba tiba tidak bisa melihat)/.test(t) ||
      /(overdosis|over dosis|kelebihan (dosis|obat|insulin|suntik)|salah (suntik|dosis)|minum (semua|banyak) obat sekaligus|keracunan)/.test(t),
    message:
      "Gejala seperti ini perlu penilaian tenaga kesehatan. Jika terasa darurat, hubungi layanan gawat darurat atau segera ke fasilitas kesehatan terdekat. Saya tidak memberi saran makanan untuk situasi ini.",
  },
  {
    code: "GLUCOSE_EXTREME",
    decision: "NEEDS_CLINICAL_REVIEW",
    test: (t, raw) =>
      /((gula|glukosa|gd[sp]?)( darah)? (sangat |lagi |tiba tiba )?(rendah|tinggi) (sekali|banget|parah)|(gula|glukosa)( darah)? (sangat|amat) (rendah|tinggi)|(gula|glukosa|gd[sp]?)( darah)? (drop|anjlok|turun drastis|naik drastis|tembus)|blood sugar (is )?(very|really|too) (low|high))/.test(t) ||
      extremeGlucose(raw) !== null,
    message:
      "Angka gula darah seperti ini perlu segera ditangani. Ikuti rencana penanganan dari dokter atau tenaga kesehatanmu. Jika disertai lemas berat, bingung, muntah, atau pingsan, hubungi layanan gawat darurat atau segera ke fasilitas kesehatan terdekat. Saya tidak memberi saran makanan atau obat untuk situasi ini.",
  },
  {
    code: "SYMPTOM_REVIEW",
    decision: "NEEDS_CLINICAL_REVIEW",
    test: re(/(luka( di| pada)? kaki( yang)? (tidak|belum|susah|lama|tak) (sembuh|kering)|luka( yang)? (tidak|belum|susah|lama|tak) (sembuh|kering)|luka (bernanah|membusuk|menghitam|berbau)|bernanah|gangren|(jari|kaki|kuku|telapak)( kaki)? (menghitam|membiru|kehitaman|kebiruan)|kaki (bengkak|kebas|mati rasa|baal)|kesemutan|\bkebas\b|mati rasa|haus terus|sering haus|sering (kencing|pipis|buang air kecil)|(kencing|pipis) terus|(pandangan|penglihatan|mata) (kabur|buram)|demam (tinggi|terus|tidak turun))/),
    message:
      "Keluhan seperti ini sebaiknya diperiksa tenaga kesehatan, apalagi pada diabetes. Buat janji dengan dokter atau puskesmas dalam waktu dekat. Jika memburuk dengan cepat, disertai demam tinggi, atau luka menghitam, segera ke fasilitas kesehatan. Saya tidak memberi saran makanan atau aktivitas untuk keluhan ini.",
  },
  {
    code: "INJURY_OR_PAIN",
    decision: "NEEDS_CLINICAL_REVIEW",
    test: re(/(cedera|\bnyeri|ngilu|encok|sakit (kaki|lutut|punggung|pinggang|sendi|otot|kepala|pinggul|bahu|leher)|(kepala|lutut|punggung|pinggang|sendi|otot) (sakit|nyeri|pusing)|\bpusing|keseleo|terkilir|patah tulang|tulang patah|(kaki|tangan|jari) patah|\bmemar|\binjur|\bpain\b|hurts)/),
    message: "Jika kamu sedang cedera, nyeri, atau pusing, sebaiknya periksakan ke tenaga kesehatan dulu. Saya tidak menyarankan aktivitas dalam kondisi ini.",
  },
  {
    code: "INTENSITY_ESCALATION",
    decision: "BLOCKED",
    test: re(/(tambah intensitas|naikkan intensitas|tingkatkan intensitas|lebih berat|lebih keras|(latihan|olahraga|intensitas|tenaga|beban|kecepatan|lari) maksimal(?! \d)|sampai maksimal|semaksimal mungkin|sampai kelelahan|sampai muntah|maraton|marathon|\bhiit\b|push my limit|increase intensity)/),
    message:
      "Saya tidak menaikkan intensitas aktivitas. Saya hanya menawarkan pilihan yang tidak melebihi apa yang sudah kamu lakukan. Konsultasikan dengan tenaga kesehatan atau pelatih bila ingin meningkatkan latihan.",
  },
  {
    code: "MEDICATION_ADVICE",
    decision: "BLOCKED",
    test: re(/(dosis|takaran obat|(ubah|ganti|naikkan|turunkan|kurangi|tambah|lewati|skip|stop|berhenti( minum)?|hentikan) (obat|insulin)|(obat|insulin)( [a-z]+)? (dikurangi|ditambah|diganti|dihentikan|dilewati|diskip)|berhenti minum obat|(lupa|telat|terlambat) (minum|suntik) (obat|insulin)\b.*\b(boleh|harus|sebaiknya|perlu|langsung|sekarang|diganti|dobel|double)|(minum|suntik)( obat| insulin)? (dobel|double|dua kali lipat)|(obat|insulin|dosis) (dobel|double)|dobel (obat|dosis|insulin)|double dose|suntik insulin|insulin|metformin|glimepirid|gliklazid|glikazid|glibenklamid|glikuidon|glipizid|akarbose|acarbose|pioglitazon|sitagliptin|vildagliptin|linagliptin|saxagliptin|dapagliflozin|empagliflozin|canagliflozin|novorapid|lantus|levemir|humalog|apidra|tresiba|ozempic|semaglutid|liraglutid|medication dose|change my medication)/),
    message: "Saya tidak dapat menyarankan perubahan obat atau dosis. Bicarakan dengan dokter atau apotekermu. Saya bisa membantu mencari pilihan makanan yang tidak berkaitan dengan pengobatan.",
  },
  {
    code: "DIAGNOSIS_REQUEST",
    decision: "BLOCKED",
    test: re(/(apa(kah)? saya (ini )?(terkena |kena |menderita |punya |mengidap |sakit |termasuk |sudah )?(diabetes|prediabetes|sakit gula|kencing manis)|saya (terkena|kena|menderita) diabetes\?|tolong (diagnosis|diagnosa)|diagnosa saya|diagnosis saya|(hba1c|a1c|hasil lab|hasil cek darah)\b.*\b(artinya|normal|bahaya|berbahaya)|do i have diabetes|am i diabetic)/),
    message: "beOkay bukan alat diagnosis. Pemeriksaan dan diagnosis dilakukan oleh tenaga kesehatan.",
  },
  {
    code: "HEALTH_CLAIM_REQUEST",
    decision: "BLOCKED",
    test: re(/(menyembuhkan|pasti (menurunkan|turun)|menurunkan (kadar )?gula|bikin gula (darah )?(turun|normal)|gula (darah )?(cepat|langsung) turun|sembuh (dari )?(diabetes|sakit gula|kencing manis)|obat (alami|herbal)|herbal (untuk|buat) (diabetes|gula)|jamu (untuk |buat )?(diabetes|gula|kencing manis)|reverse diabetes|cure diabetes|lower my blood sugar)/),
    message: "Saya tidak dapat menjanjikan makanan tertentu menyembuhkan atau menurunkan gula darah. Saya bisa membantu mencari pilihan makanan berdasarkan data gizi dan preferensimu.",
  },
  {
    code: "EXTREME_RESTRICTION",
    decision: "BLOCKED",
    test: (t) =>
      prolongedFast(t) ||
      /(puasa (total|ekstrem|extreme)|diet (ekstrem|0 kalori|nol kalori)|tidak makan sama sekali|(mau|ingin|akan|rencana|coba|mencoba)\b.*\b(tidak|skip) makan (seharian|berhari hari)|(tidak|skip) makan (seharian|berhari hari) (biar|supaya|untuk|agar)|makan (cuma|hanya) sekali (sehari|seminggu|dua hari)|(di bawah|kurang dari|cuma|hanya) (300|400|500|600|700|800) (kalori|kkal) (sehari|per hari|seharian)|sengaja muntah|memuntahkan makanan|muntahin makanan|pencahar (biar|supaya|untuk)|\bstarve)/.test(t),
    message: "Saya tidak menyarankan pembatasan makan yang ekstrem. Jika kamu ingin mengubah pola makan secara signifikan, konsultasikan dengan tenaga kesehatan.",
  },
];

export const SAFETY_RULE_CODES: readonly SafetyCode[] = RULES.map((r) => r.code);

export function safetyMessageFor(code: SafetyCode): string {
  return RULES.find((r) => r.code === code)!.message;
}

export function screenRequest(text: string): ScreenDecision {
  const t = canonical(text);
  for (const r of RULES) if (r.test(t, text)) return { decision: r.decision, code: r.code, message: r.message, urgent: URGENT_CODES.has(r.code) };
  return { decision: "ALLOWED" };
}

export type CandidateForValidation = {
  name: string;
  source: string;
  provenance: string;
  per100g: Record<string, number | null>;
};

/** Kandidat tanpa sumber, tanpa nama, atau dengan angka di luar rentang tidak boleh ditawarkan (tidak ada nilai karangan). */
export function validateCandidate(c: CandidateForValidation): { ok: true } | { ok: false; reason: string } {
  if (!c.name || c.name.trim().length === 0) return { ok: false, reason: "NO_NAME" };
  if (!c.source || !c.provenance) return { ok: false, reason: "NO_SOURCE" };
  const limits: Record<string, number> = { calories: 950, carbohydrates: 100, protein: 100, fat: 100, fiber: 100 };
  for (const [k, max] of Object.entries(limits)) {
    const v = c.per100g[k];
    if (v !== null && v !== undefined && (typeof v !== "number" || !Number.isFinite(v) || v < 0 || v > max)) return { ok: false, reason: `IMPLAUSIBLE_${k.toUpperCase()}` };
  }
  return { ok: true };
}

/** Penjelasan yang dihasilkan tidak boleh memuat klaim terlarang. Dipakai sebagai gerbang terakhir untuk teks apa pun, termasuk teks buatan model nanti. */
export const FORBIDDEN_CLAIMS = /(menyembuhkan|pasti menurunkan|menurunkan gula darah|dosis|diagnosis[: ]+anda|aman untuk penderita|bebas risiko|obat)/i;
export function explanationIsSafe(text: string): boolean {
  return !FORBIDDEN_CLAIMS.test(text);
}
