import { GLUCOSE_LIMITS, SAFETY_POLICY_VERSION } from "../agent/agent.safety.ts";

export const GLUCOSE_ALERT_TEXT = {
  LOW: {
    title: "Angka ini di bawah 70 mg/dL",
    message: "Bila kamu merasa gemetar, berkeringat, bingung, atau lemas, ikuti rencana penanganan gula rendah dari tenaga kesehatanmu. Bila tidak membaik, pingsan, atau sulit sadar, segera hubungi layanan darurat 119.",
  },
  HIGH: {
    title: "Angka ini 300 mg/dL atau lebih",
    message: "Periksa ulang dengan alat yang sama bila memungkinkan. Bila tetap tinggi, atau disertai muntah, sangat haus, sesak, atau lemas berat, segera hubungi tenaga kesehatan atau layanan darurat 119.",
  },
} as const;

export type GlucoseAlert = { level: "LOW" | "HIGH"; title: string; message: string; policyVersion: string; thresholdMgDl: number };

export function glucoseAlert(valueMgDl: number): GlucoseAlert | null {
  if (valueMgDl < GLUCOSE_LIMITS.mgdlLow) return { level: "LOW", ...GLUCOSE_ALERT_TEXT.LOW, policyVersion: SAFETY_POLICY_VERSION, thresholdMgDl: GLUCOSE_LIMITS.mgdlLow };
  if (valueMgDl >= GLUCOSE_LIMITS.mgdlHigh) return { level: "HIGH", ...GLUCOSE_ALERT_TEXT.HIGH, policyVersion: SAFETY_POLICY_VERSION, thresholdMgDl: GLUCOSE_LIMITS.mgdlHigh };
  return null;
}
