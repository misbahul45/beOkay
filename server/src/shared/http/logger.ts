export type LogFields = Record<string, string | number | boolean | undefined>;

export function logEvent(level: "info" | "warn" | "error", event: string, fields: LogFields = {}) {
  const line = JSON.stringify({ ts: new Date().toISOString(), level, event, ...fields });
  if (level === "error") console.error(line);
  else console.log(line);
}
