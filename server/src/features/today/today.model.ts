export type TodayIdentity = { displayName: string; timezone: string; glucoseUnit: string };

export function buildToday(identity: TodayIdentity, now: Date) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: identity.timezone, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", hourCycle: "h23",
  }).formatToParts(now);
  const part = (type: string) => parts.find((item) => item.type === type)!.value;
  const hour = Number(part("hour"));
  const greeting = hour >= 5 && hour < 11 ? "Selamat pagi" : hour >= 11 && hour < 15 ? "Selamat siang" : hour >= 15 && hour < 18 ? "Selamat sore" : "Selamat malam";
  return {
    ...identity,
    date: `${part("year")}-${part("month")}-${part("day")}`,
    greeting,
    generatedAt: now.toISOString(),
    computationVersion: "today-foundation-v1",
    analyticsState: "NOT_AVAILABLE" as const,
    metrics: ["glucose", "nutrition", "activity", "medication"].map((domain) => ({
      domain, availability: "NOT_IMPLEMENTED" as const, value: null,
    })),
    goals: { availability: "NOT_IMPLEMENTED" as const, items: [] },
    timeline: { availability: "NOT_IMPLEMENTED" as const, items: [] },
  };
}
