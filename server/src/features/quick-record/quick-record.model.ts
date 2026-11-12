export const QUICK_RECORD_VERSION = "quick-record-v1";
export const LOOKBACK_DAYS = 30;
export const MAX_SUGGESTIONS = 5;

export type MealItemTemplate = { foodId: string | null; name: string; quantity: number; unit: string; grams: number | null; gramsBasis: string | null };
export type MealSample = { id: string; category: string; consumedAt: Date; items: MealItemTemplate[] };
export type ActivitySample = { id: string; activityType: string; durationMinutes: number; reportedIntensity: string; startedAt: Date };

export function mealSignature(m: Pick<MealSample, "category" | "items">) {
  const items = m.items.map((i) => `${i.foodId ?? i.name.trim().toLowerCase()}|${i.quantity}|${i.unit}|${i.grams ?? ""}`).sort();
  return `${m.category}#${items.join(";")}`;
}

export function mealTitle(items: MealItemTemplate[]) {
  const names = items.map((i) => i.name);
  return names.length <= 3 ? names.join(", ") : `${names.slice(0, 3).join(", ")} +${names.length - 3}`;
}

export function rankMeals(samples: MealSample[]) {
  const groups = new Map<string, { latest: MealSample; count: number }>();
  for (const s of samples) {
    const key = mealSignature(s);
    const g = groups.get(key);
    if (!g) groups.set(key, { latest: s, count: 1 });
    else {
      g.count++;
      if (s.consumedAt > g.latest.consumedAt) g.latest = s;
    }
  }
  return [...groups.entries()]
    .sort(([, a], [, b]) => b.count - a.count || b.latest.consumedAt.getTime() - a.latest.consumedAt.getTime())
    .slice(0, MAX_SUGGESTIONS)
    .map(([key, g]) => ({ key, count: g.count, latest: g.latest }));
}

export const ACTIVITY_LABEL: Record<string, string> = { walking: "Jalan kaki", cycling: "Bersepeda", running: "Lari", strength: "Latihan kekuatan", other: "Aktivitas" };

export function rankActivities(samples: ActivitySample[]) {
  const groups = new Map<string, { latest: ActivitySample; count: number }>();
  for (const s of samples) {
    const key = `${s.activityType}|${s.durationMinutes}|${s.reportedIntensity}`;
    const g = groups.get(key);
    if (!g) groups.set(key, { latest: s, count: 1 });
    else {
      g.count++;
      if (s.startedAt > g.latest.startedAt) g.latest = s;
    }
  }
  return [...groups.entries()]
    .sort(([, a], [, b]) => b.count - a.count || b.latest.startedAt.getTime() - a.latest.startedAt.getTime())
    .slice(0, MAX_SUGGESTIONS)
    .map(([key, g]) => ({ key, count: g.count, latest: g.latest }));
}

export function categoryForHour(hour: number) {
  if (hour >= 4 && hour < 10) return "breakfast";
  if (hour >= 10 && hour < 15) return "lunch";
  if (hour >= 17 && hour < 22) return "dinner";
  return "snack";
}
