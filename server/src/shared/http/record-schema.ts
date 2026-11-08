import { z } from "zod";
export const recordTimestamp = z.iso
  .datetime({ offset: true })
  .refine((value) => {
    const parsed = new Date(value);
    return (
      Number.isFinite(parsed.getTime()) &&
      value.slice(0, 10) ===
        new Date(value.slice(0, 10) + "T00:00:00Z")
          .toISOString()
          .slice(0, 10) &&
      parsed.getUTCFullYear() >= 1900 &&
      parsed.getTime() <= Date.now() + 300000
    );
  }, "invalid event timestamp");
export function localRecordTime(time: Date, timezone: string) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(time);
  const p = (type: string) => parts.find((x) => x.type === type)!.value;
  return {
    localDate: `${p("year")}-${p("month")}-${p("day")}`,
    localTime: `${p("hour")}:${p("minute")}`,
    timezone,
  };
}
