import type { LabelledQuery } from "./retrieval-queries.ts";

export const RETRIEVAL_QUERIES_HELDOUT: LabelledQuery[] = [
  { query: "apa yang bisa kulakukan supaya tidak jadi diabetes", lane: "A_PUBLIC_HEALTH", journey: "PREVENTION", relevant: ["edu:cegah-diabetes@v1"] },
  { query: "dokter bilang gula darahku di atas normal tapi belum diabetes", lane: "A_PUBLIC_HEALTH", journey: "PREVENTION", relevant: ["edu:cegah-diabetes@v1"] },
  { query: "kapan sebaiknya cek gula darah ke puskesmas", lane: "A_PUBLIC_HEALTH", journey: "PREVENTION", relevant: ["edu:pemeriksaan-rutin@v1"] },
  { query: "luka di kakiku lama sembuhnya", lane: "A_PUBLIC_HEALTH", journey: "WELLNESS", relevant: ["edu:pemeriksaan-rutin@v1"] },
  { query: "sering terbangun malam dan ngantuk siang", lane: "A_PUBLIC_HEALTH", journey: "WELLNESS", relevant: ["edu:tidur-dan-pulih@v1"] },
  { query: "apakah jam tangan bisa mengukur tidur dengan benar", lane: "A_PUBLIC_HEALTH", journey: "PREVENTION", relevant: ["edu:tidur-dan-pulih@v1"] },
  { query: "keringat dingin dan gemetar setelah minum obat", lane: "A_PUBLIC_HEALTH", journey: "T2DM_SUPPORT", relevant: ["edu:hipoglikemia@v1"] },
  { query: "cara membaca informasi nilai gizi di bungkus", lane: "A_PUBLIC_HEALTH", journey: "PREVENTION", relevant: ["edu:label-gizi@v1"] },
  { query: "berapa banyak nasi yang pas sekali makan", lane: "A_PUBLIC_HEALTH", journey: "WELLNESS", relevant: ["edu:karbohidrat-porsi@v1"] },
  { query: "aman tidak olahraga kalau dada terasa sakit", lane: "A_PUBLIC_HEALTH", journey: "T2DM_SUPPORT", relevant: ["edu:aktivitas-aman@v1"] },
  { query: "boleh puasa ramadan kalau diabetes", lane: "A_PUBLIC_HEALTH", journey: "T2DM_SUPPORT", relevant: ["edu:puasa-ramadan@v1"] },
  { query: "aku selalu kelupaan isi catatan makan", lane: "C_BEHAVIOR_STRATEGY", journey: "PREVENTION", relevant: ["strategy:FORGOT_REMINDER@v1", "strategy:FORGOT_PAIR@v1"] },
  { query: "kerjaan padat jadi tidak sempat jalan", lane: "C_BEHAVIOR_STRATEGY", journey: "WELLNESS", relevant: ["strategy:TIME_SPLIT@v1", "strategy:TIME_ANCHOR@v1", "strategy:TIME_PICK_SLOT@v1"] },
  { query: "pulang kerja badanku lemas sekali", lane: "C_BEHAVIOR_STRATEGY", journey: "T2DM_SUPPORT", relevant: ["strategy:ENERGY_LIGHT@v1", "strategy:ENERGY_BEST_TIME@v1", "strategy:ENERGY_ASK@v1"] },
  { query: "lagi nggak semangat sama sekali", lane: "C_BEHAVIOR_STRATEGY", journey: "PREVENTION", relevant: ["strategy:MOTIVATION_SMALLER@v1", "strategy:MOTIVATION_BUDDY@v1", "strategy:MOTIVATION_WHY@v1"] },
  { query: "rekomendasi film akhir pekan", lane: "A_PUBLIC_HEALTH", journey: "WELLNESS", relevant: [] },
  { query: "cara memperbaiki motor mogok", lane: "C_BEHAVIOR_STRATEGY", journey: "PREVENTION", relevant: [] },
  { query: "dosis insulin malam berapa unit", lane: "A_PUBLIC_HEALTH", journey: "PREVENTION", relevant: [] },
];
