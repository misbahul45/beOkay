import { env } from "../../config/env.ts";
import { forbidden } from "../../shared/errors/app-error.ts";

export const SIMULATED_SOURCE = "simulated";

export type SimulationConfig = { nodeEnv: string; enabled: boolean };

export const simulationAllowed = (config: SimulationConfig = { nodeEnv: env.NODE_ENV, enabled: env.DEVICE_SIMULATION_ENABLED }) => config.enabled && config.nodeEnv !== "production";

export function assertSimulationAllowed(allowed: boolean = simulationAllowed()) {
  if (!allowed) throw forbidden("SIMULATION_DISABLED", "Data simulasi hanya diterima di lingkungan pengembangan atau uji.");
}
