/**
 * Keselamatan deterministik di LUAR model bahasa. Aturan berversi; tidak ada teks model yang dapat menimpanya.
 * Dua lapis: (1) penyaringan permintaan sebelum alat apa pun dijalankan, (2) validasi kandidat sebelum ditawarkan.
 */
export const SAFETY_POLICY_VERSION = "safety-policy-v1";

export type ScreenDecision =
  | { decision: "ALLOWED" }
  | { decision: "BLOCKED" | "NEEDS_CLINICAL_REVIEW"; code: string; message: string };

const norm = (s: string) => s.normalize("NFKD").replace(/\p{M}/gu, "").toLowerCase().replace(/\s+/g, " ").trim();

const RULES: { code: string; decision: "BLOCKED" | "NEEDS_CLINICAL_REVIEW"; pattern: RegExp; message: string }[] = [
  {
    code: "URGENT_SYMPTOM",
    decision: "NEEDS_CLINICAL_REVIEW",
    pattern: /(pingsan|tidak sadar|nyeri dada|sesak napas|sesak nafas|kejang|gemetar hebat|muntah terus|hipoglikemia|gula darah (sangat )?(rendah|tinggi) (sekali|banget)|chest pain|faint|seizure)/,
    message: "Gejala seperti ini perlu penilaian tenaga kesehatan. Jika terasa darurat, hubungi layanan gawat darurat atau segera ke fasilitas kesehatan terdekat. Saya tidak memberi saran makanan untuk situasi ini.",
  },
  {
    code: "INJURY_OR_PAIN",
    decision: "NEEDS_CLINICAL_REVIEW",
    pattern: /(cedera|nyeri|sakit (kaki|lutut|punggung|pinggang|sendi|otot)|pusing|keseleo|patah|injury|pain)/,
    message: "Jika kamu sedang cedera, nyeri, atau pusing, sebaiknya periksakan ke tenaga kesehatan dulu. Saya tidak menyarankan aktivitas dalam kondisi ini.",
  },
  {
    code: "INTENSITY_ESCALATION",
    decision: "BLOCKED",
    pattern: /(tambah intensitas|naikkan intensitas|lebih berat|lebih keras|maksimal|sampai kelelahan|maraton|hiit|push my limit|increase intensity)/,
    message: "Saya tidak menaikkan intensitas aktivitas. Saya hanya menawarkan pilihan yang tidak melebihi apa yang sudah kamu lakukan. Konsultasikan dengan tenaga kesehatan atau pelatih bila ingin meningkatkan latihan.",
  },
  {
    code: "MEDICATION_ADVICE",
    decision: "BLOCKED",
    pattern: /(dosis|takaran obat|ubah obat|ganti obat|naikkan obat|turunkan obat|kurangi obat|tambah obat|berhenti minum obat|stop obat|lewati obat|skip obat|suntik insulin|insulin|metformin|glimepirid|gliklazid|medication dose|change my medication)/,
    message: "Saya tidak dapat menyarankan perubahan obat atau dosis. Bicarakan dengan dokter atau apotekermu. Saya bisa membantu mencari pilihan makanan yang tidak berkaitan dengan pengobatan.",
  },
  {
    code: "DIAGNOSIS_REQUEST",
    decision: "BLOCKED",
    pattern: /(apakah saya (terkena |kena |menderita )?(diabetes|prediabetes)|saya (terkena|kena|menderita) diabetes\?|tolong diagnosis|diagnosa saya|do i have diabetes)/,
    message: "beOkay bukan alat diagnosis. Pemeriksaan dan diagnosis dilakukan oleh tenaga kesehatan.",
  },
  {
    code: "HEALTH_CLAIM_REQUEST",
    decision: "BLOCKED",
    pattern: /(menyembuhkan|pasti (menurunkan|turun)|menurunkan gula darah|obat alami|cure diabetes|lower my blood sugar)/,
    message: "Saya tidak dapat menjanjikan makanan tertentu menyembuhkan atau menurunkan gula darah. Saya bisa membantu mencari pilihan makanan berdasarkan data gizi dan preferensimu.",
  },
  {
    code: "EXTREME_RESTRICTION",
    decision: "BLOCKED",
    pattern: /(puasa (total|ekstrem|extreme)|diet (ekstrem|0 kalori|nol kalori)|tidak makan sama sekali|starve)/,
    message: "Saya tidak menyarankan pembatasan makan yang ekstrem. Jika kamu ingin mengubah pola makan secara signifikan, konsultasikan dengan tenaga kesehatan.",
  },
];

export function screenRequest(text: string): ScreenDecision {
  const t = norm(text);
  for (const r of RULES) if (r.pattern.test(t)) return { decision: r.decision, code: r.code, message: r.message };
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
