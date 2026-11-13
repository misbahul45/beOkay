import type { Journey } from "../../src/features/cohort/cohort.policy.ts";
import type { Lane } from "../../src/features/knowledge/knowledge.service.ts";

export type LabelledQuery = { query: string; lane: Lane; journey: Journey; relevant: string[] };

export const RETRIEVAL_QUERIES: LabelledQuery[] = [
  { query: "bagaimana cara mencegah diabetes", lane: "A_PUBLIC_HEALTH", journey: "PREVENTION", relevant: ["edu:cegah-diabetes@v1"] },
  { query: "apa arti prediabetes", lane: "A_PUBLIC_HEALTH", journey: "PREVENTION", relevant: ["edu:cegah-diabetes@v1"] },
  { query: "seberapa sering pemeriksaan rutin", lane: "A_PUBLIC_HEALTH", journey: "WELLNESS", relevant: ["edu:pemeriksaan-rutin@v1"] },
  { query: "sering haus dan buang air kecil", lane: "A_PUBLIC_HEALTH", journey: "PREVENTION", relevant: ["edu:pemeriksaan-rutin@v1"] },
  { query: "berapa jam tidur yang cukup", lane: "A_PUBLIC_HEALTH", journey: "WELLNESS", relevant: ["edu:tidur-dan-pulih@v1"] },
  { query: "data tidur jam tangan akurat", lane: "A_PUBLIC_HEALTH", journey: "T2DM_SUPPORT", relevant: ["edu:tidur-dan-pulih@v1"] },
  { query: "gula darah rendah gemetar", lane: "A_PUBLIC_HEALTH", journey: "T2DM_SUPPORT", relevant: ["edu:hipoglikemia@v1"] },
  { query: "membaca label gizi kemasan", lane: "A_PUBLIC_HEALTH", journey: "WELLNESS", relevant: ["edu:label-gizi@v1"] },
  { query: "porsi karbohidrat nasi", lane: "A_PUBLIC_HEALTH", journey: "PREVENTION", relevant: ["edu:karbohidrat-porsi@v1"] },
  { query: "olahraga aman berhenti bila nyeri dada", lane: "A_PUBLIC_HEALTH", journey: "WELLNESS", relevant: ["edu:aktivitas-aman@v1"] },
  { query: "merawat kaki luka", lane: "A_PUBLIC_HEALTH", journey: "T2DM_SUPPORT", relevant: ["edu:perawatan-kaki@v1"] },
  { query: "arti hba1c", lane: "A_PUBLIC_HEALTH", journey: "T2DM_SUPPORT", relevant: ["edu:mengenal-dmt2@v1"] },
  { query: "aku sering lupa mencatat", lane: "C_BEHAVIOR_STRATEGY", journey: "WELLNESS", relevant: ["strategy:FORGOT_REMINDER@v1", "strategy:FORGOT_PAIR@v1"] },
  { query: "tidak punya waktu sibuk kerja", lane: "C_BEHAVIOR_STRATEGY", journey: "PREVENTION", relevant: ["strategy:TIME_SPLIT@v1", "strategy:TIME_ANCHOR@v1", "strategy:TIME_PICK_SLOT@v1"] },
  { query: "capek tidak bertenaga", lane: "C_BEHAVIOR_STRATEGY", journey: "T2DM_SUPPORT", relevant: ["strategy:ENERGY_LIGHT@v1", "strategy:ENERGY_BEST_TIME@v1", "strategy:ENERGY_ASK@v1"] },
  { query: "malas tidak ada motivasi", lane: "C_BEHAVIOR_STRATEGY", journey: "WELLNESS", relevant: ["strategy:MOTIVATION_SMALLER@v1", "strategy:MOTIVATION_BUDDY@v1", "strategy:MOTIVATION_WHY@v1"] },
  { query: "resep kue bolu pandan", lane: "A_PUBLIC_HEALTH", journey: "WELLNESS", relevant: [] },
  { query: "harga saham hari ini", lane: "C_BEHAVIOR_STRATEGY", journey: "WELLNESS", relevant: [] },
];
