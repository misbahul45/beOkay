export const GLUCOSE_UNITS = ["mg/dL", "mmol/L"] as const;
export type GlucoseUnit = (typeof GLUCOSE_UNITS)[number];

const MG_DL_PER_MMOL_L = 18.016;

export function mgDlToMmolL(mgDl: number): number {
  return Math.round((mgDl / MG_DL_PER_MMOL_L) * 10) / 10;
}

export function mmolLToMgDl(mmolL: number): number {
  return Math.round(mmolL * MG_DL_PER_MMOL_L);
}

export function convertGlucose(value: number, from: GlucoseUnit, to: GlucoseUnit): number {
  if (from === to) return value;
  return from === "mg/dL" ? mgDlToMmolL(value) : mmolLToMgDl(value);
}
