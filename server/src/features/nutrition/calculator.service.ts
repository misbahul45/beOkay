import { prisma } from "../../infrastructure/database/prisma.ts";
import { notFound } from "../../shared/errors/app-error.ts";
import { consentService } from "../consent/consent.service.ts";
import { numericNutrients } from "./nutrition.model.ts";
import { calculateMeal, type PortionInput } from "./portion.model.ts";
import type { CalculateRequest, MeasureInput } from "./calculator.schema.ts";

async function visibleFood(userId: string, id: string) {
  const food = await prisma.foodCatalog.findFirst({ where: { id, OR: [{ userId }, { userId: null }] } });
  if (!food) throw notFound("FOOD_NOT_FOUND", "Makanan tidak ditemukan.");
  return food;
}

export const calculatorService = {
  async listMeasures(userId: string, foodId: string) {
    await consentService.requireConsent(userId, "health_data_processing");
    await visibleFood(userId, foodId);
    const rows = await prisma.foodPortionMeasure.findMany({ where: { userId, foodId }, orderBy: [{ label: "asc" }] });
    return { items: rows.map((r) => ({ id: r.id, foodId: r.foodId, label: r.label, grams: r.grams.toNumber(), basis: r.basis })) };
  },

  async addMeasure(userId: string, foodId: string, input: MeasureInput) {
    await consentService.requireConsent(userId, "health_data_processing");
    await visibleFood(userId, foodId);
    const row = await prisma.foodPortionMeasure.upsert({
      where: { userId_foodId_label: { userId, foodId, label: input.label } },
      create: { userId, foodId, ...input },
      update: { grams: input.grams, basis: input.basis },
    });
    return { id: row.id, foodId, label: row.label, grams: row.grams.toNumber(), basis: row.basis };
  },

  /** Hitung tanpa menyimpan. Berat tidak diketahui → nilai kosong, tidak ditebak. */
  async calculate(userId: string, req: CalculateRequest) {
    await consentService.requireConsent(userId, "health_data_processing");
    const inputs: PortionInput[] = [];
    for (const item of req.items) {
      if (item.foodId) {
        const food = await visibleFood(userId, item.foodId);
        const measure = item.measureId
          ? await prisma.foodPortionMeasure.findFirst({ where: { id: item.measureId, userId, foodId: item.foodId } })
          : null;
        if (item.measureId && !measure) throw notFound("MEASURE_NOT_FOUND", "Ukuran porsi tidak ditemukan untuk makanan ini.");
        inputs.push({
          name: item.name ?? food.name,
          per100g: numericNutrients(food),
          grams: item.grams ?? null,
          gramsBasis: item.gramsBasis,
          quantity: item.quantity,
          measure: measure ? { id: measure.id, label: measure.label, grams: measure.grams.toNumber(), basis: measure.basis as "weighed" | "user_estimate" } : null,
        });
      } else {
        inputs.push({ name: item.name ?? "Makanan", per100g: item.per100g!, grams: item.grams ?? null, gramsBasis: item.gramsBasis });
      }
    }
    return { ...calculateMeal(inputs), computationVersion: "portion-calc-v1" };
  },
};
