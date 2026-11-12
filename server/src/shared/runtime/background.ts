import { waitUntil } from "@vercel/functions";
import { logEvent } from "../http/logger.ts";

export function background(task: Promise<unknown>, label = "background_task") {
  const guarded = task.catch((e) => logEvent("error", `${label}_failed`, { name: e instanceof Error ? e.name : "unknown" }));
  try {
    waitUntil(guarded);
  } catch {
    return guarded;
  }
  return guarded;
}
