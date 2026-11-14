import { SIMULATED_SOURCE } from "./simulation.ts";

export const DEVICE_TYPES = ["watch", "phone", "ring", "scale", "chest_strap", "fitness_band", "head_mounted", "unknown"] as const;
export type DeviceType = (typeof DEVICE_TYPES)[number];

export const RECORDING_METHODS = ["automatic", "active", "manual", "unknown"] as const;
export type RecordingMethod = (typeof RECORDING_METHODS)[number];

export type Provenance = "PHONE_RECORDED" | "WATCH_RECORDED" | "OTHER_DEVICE" | "USER_ENTERED" | "UNKNOWN" | "SIMULATED";
export type WatchVerification = "WATCH_NOT_VERIFIED" | "WATCH_SOURCE_DETECTED" | "WATCH_HARDWARE_VERIFIED";

export type ProvenanceInput = { source: string; deviceType?: string | null; recordingMethod?: string | null };

export function classifyProvenance(r: ProvenanceInput): Provenance {
  if (r.source === SIMULATED_SOURCE) return "SIMULATED";
  if (r.recordingMethod === "manual") return "USER_ENTERED";
  if (r.deviceType === "watch") return "WATCH_RECORDED";
  if (r.deviceType === "phone") return "PHONE_RECORDED";
  if (r.deviceType && r.deviceType !== "unknown") return "OTHER_DEVICE";
  return "UNKNOWN";
}

export function watchVerification(rows: ProvenanceInput[]): WatchVerification {
  return rows.some((r) => classifyProvenance(r) === "WATCH_RECORDED") ? "WATCH_SOURCE_DETECTED" : "WATCH_NOT_VERIFIED";
}

export function provenanceCounts(rows: ProvenanceInput[]) {
  const counts: Record<Provenance, number> = { PHONE_RECORDED: 0, WATCH_RECORDED: 0, OTHER_DEVICE: 0, USER_ENTERED: 0, UNKNOWN: 0, SIMULATED: 0 };
  for (const r of rows) counts[classifyProvenance(r)]++;
  return counts;
}
