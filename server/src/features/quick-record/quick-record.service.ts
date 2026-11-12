import { prisma } from "../../infrastructure/database/prisma.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { consentService } from "../consent/consent.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { ACTIVITY_LABEL, LOOKBACK_DAYS, QUICK_RECORD_VERSION, categoryForHour, mealTitle, rankActivities, rankMeals, type MealItemTemplate } from "./quick-record.model.ts";

const DAY = 86_400_000;

export const quickRecordService = {
  async suggestions(userId: string, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    const { timezone } = await preferencesService.get(userId);
    const since = new Date(now.getTime() - LOOKBACK_DAYS * DAY);
    const [meals, activities] = await Promise.all([
      prisma.mealLog.findMany({ where: { userId, archivedAt: null, consumedAt: { gte: since } }, include: { items: { orderBy: { id: "asc" } } }, orderBy: { consumedAt: "desc" }, take: 200 }),
      prisma.activitySession.findMany({ where: { userId, archivedAt: null, source: "manual", startedAt: { gte: since } }, orderBy: { startedAt: "desc" }, take: 200, select: { id: true, activityType: true, durationMinutes: true, reportedIntensity: true, startedAt: true } }),
    ]);
    const foodIds = [...new Set(meals.flatMap((m) => m.items.map((i) => i.foodId).filter((v): v is string => v !== null)))];
    const visible = new Set((await prisma.foodCatalog.findMany({ where: { id: { in: foodIds }, OR: [{ userId }, { userId: null }] }, select: { id: true } })).map((f) => f.id));
    const samples = meals.map((m) => ({
      id: m.id,
      category: m.category,
      consumedAt: m.consumedAt,
      items: [...m.items].sort((x, y) => x.name.localeCompare(y.name, "id")).map<MealItemTemplate>((i) => ({ foodId: i.foodId && visible.has(i.foodId) ? i.foodId : null, name: i.name, quantity: i.quantity.toNumber(), unit: i.unit, grams: i.unit === "g" ? null : (i.grams?.toNumber() ?? null), gramsBasis: i.unit === "g" ? null : i.grams ? i.gramsBasis : null })),
    }));
    const hour = Number(localRecordTime(now, timezone).localTime.slice(0, 2));
    return {
      meals: rankMeals(samples).map((g) => ({
        key: g.key,
        title: mealTitle(g.latest.items),
        category: g.latest.category,
        count: g.count,
        lastAt: g.latest.consumedAt.toISOString(),
        last: localRecordTime(g.latest.consumedAt, timezone),
        lastMealId: g.latest.id,
        nutritionKnown: g.latest.items.every((i) => i.foodId !== null),
        template: { category: g.latest.category, items: g.latest.items.map((i) => ({ ...(i.foodId ? { foodId: i.foodId } : {}), name: i.name, quantity: i.quantity, unit: i.unit, grams: i.grams, gramsBasis: i.gramsBasis })) },
      })),
      activities: rankActivities(activities).map((g) => ({
        key: g.key,
        title: `${ACTIVITY_LABEL[g.latest.activityType] ?? "Aktivitas"} ${g.latest.durationMinutes} menit`,
        count: g.count,
        lastAt: g.latest.startedAt.toISOString(),
        last: localRecordTime(g.latest.startedAt, timezone),
        template: { activityType: g.latest.activityType, durationMinutes: g.latest.durationMinutes, reportedIntensity: g.latest.reportedIntensity },
      })),
      suggestedCategory: categoryForHour(hour),
      lookbackDays: LOOKBACK_DAYS,
      computationVersion: QUICK_RECORD_VERSION,
    };
  },
};
