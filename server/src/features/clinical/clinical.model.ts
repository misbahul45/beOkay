export const VITAL_KINDS = ["weight", "height", "waist", "blood_pressure"] as const;
export type VitalKind = (typeof VITAL_KINDS)[number];

export const VITAL_RULES: Record<VitalKind, { unit: string; min: number; max: number; min2?: number; max2?: number; label: string }> = {
  weight: { unit: "kg", min: 10, max: 500, label: "Berat badan" },
  height: { unit: "cm", min: 50, max: 250, label: "Tinggi badan" },
  waist: { unit: "cm", min: 30, max: 300, label: "Lingkar pinggang" },
  blood_pressure: { unit: "mmHg", min: 40, max: 300, min2: 20, max2: 200, label: "Tekanan darah" },
};

export const LAB_TESTS = ["hba1c", "fasting_glucose", "ldl", "hdl", "total_cholesterol", "triglycerides", "creatinine", "egfr", "urine_acr"] as const;
export type LabTest = (typeof LAB_TESTS)[number];

export const LAB_RULES: Record<LabTest, { units: Record<string, [number, number]>; label: string }> = {
  hba1c: { units: { "%": [2, 25], "mmol/mol": [1, 300] }, label: "HbA1c" },
  fasting_glucose: { units: { "mg/dL": [10, 2000], "mmol/L": [0.5, 111] }, label: "Glukosa puasa (lab)" },
  ldl: { units: { "mg/dL": [1, 1000], "mmol/L": [0.03, 26] }, label: "Kolesterol LDL" },
  hdl: { units: { "mg/dL": [1, 300], "mmol/L": [0.03, 8] }, label: "Kolesterol HDL" },
  total_cholesterol: { units: { "mg/dL": [10, 2000], "mmol/L": [0.3, 52] }, label: "Kolesterol total" },
  triglycerides: { units: { "mg/dL": [5, 20000], "mmol/L": [0.05, 226] }, label: "Trigliserida" },
  creatinine: { units: { "mg/dL": [0.05, 30], "umol/L": [4, 2700] }, label: "Kreatinin" },
  egfr: { units: { "mL/min/1.73m2": [1, 250] }, label: "eGFR" },
  urine_acr: { units: { "mg/g": [0.1, 50000], "mg/mmol": [0.01, 5650] }, label: "Rasio albumin-kreatinin urin" },
};

export const HBA1C_INTERVAL_DAYS = 90;
export const CLINICAL_SUMMARY_VERSION = "clinical-summary-v1";

export function vitalProblem(kind: VitalKind, unit: string, value: number, value2: number | null): string | null {
  const r = VITAL_RULES[kind];
  if (unit !== r.unit) return "UNIT_NOT_ALLOWED";
  if (value < r.min || value > r.max) return "VALUE_OUT_OF_RANGE";
  if (kind === "blood_pressure") {
    if (value2 === null || value2 < r.min2! || value2 > r.max2!) return "VALUE_OUT_OF_RANGE";
    if (value <= value2) return "SYSTOLIC_NOT_ABOVE_DIASTOLIC";
  } else if (value2 !== null) return "SECOND_VALUE_NOT_ALLOWED";
  return null;
}

export function labProblem(test: LabTest, unit: string, value: number): string | null {
  const range = LAB_RULES[test].units[unit];
  if (!range) return "UNIT_NOT_ALLOWED";
  if (value < range[0] || value > range[1]) return "VALUE_OUT_OF_RANGE";
  return null;
}

export function change(latest: number | null, previous: number | null): { difference: number; direction: "UP" | "DOWN" | "SAME" } | null {
  if (latest === null || previous === null) return null;
  const difference = Math.round((latest - previous) * 1000) / 1000;
  return { difference, direction: difference > 0 ? "UP" : difference < 0 ? "DOWN" : "SAME" };
}

export function hba1cStatus(lastSampledAt: string | null, today: string) {
  if (!lastSampledAt) return { status: "NONE" as const, lastSampledAt: null, dueOn: null, daysSince: null };
  const daysSince = Math.round((Date.parse(today + "T00:00:00Z") - Date.parse(lastSampledAt + "T00:00:00Z")) / 86_400_000);
  const dueOn = new Date(Date.parse(lastSampledAt + "T00:00:00Z") + HBA1C_INTERVAL_DAYS * 86_400_000).toISOString().slice(0, 10);
  return { status: daysSince >= HBA1C_INTERVAL_DAYS ? ("DUE" as const) : ("RECENT" as const), lastSampledAt, dueOn, daysSince };
}
