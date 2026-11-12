import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { notFound } from "../../shared/errors/app-error.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { consentService } from "../consent/consent.service.ts";
import { glucoseAlert } from "../glucose/glucose.alerts.ts";
import { GLUCOSE_COUNTED_QUALITY, displayGlucose } from "../glucose/glucose.model.ts";
import { nutritionService } from "../nutrition/nutrition.service.ts";
import type { GlucoseUnit } from "../preferences/glucose-units.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { CONTEXT_LABEL, CONTEXT_VERSION, WINDOW_DAYS, carbLine, compare, glucoseLine, insufficientLine, pairAround } from "./record-context.model.ts";

const DAY = 86_400_000;
const NOT_CAUSAL = "Dua angka di sekitar waktu makan ini, bukan sebab-akibat. Banyak hal lain ikut memengaruhi gula darah.";

async function requireBoth(userId: string) {
  await consentService.requireConsent(userId, "health_data_processing");
  await consentService.requireConsent(userId, "descriptive_summaries");
}

export const recordContextService = {
  async glucose(userId: string, id: string) {
    await requireBoth(userId);
    const row = await prisma.glucoseObservation.findFirst({ where: { id, userId } });
    if (!row) throw notFound("GLUCOSE_NOT_FOUND", "Pengukuran tidak ditemukan.");
    const { timezone, glucoseUnit } = await preferencesService.get(userId);
    const unit = glucoseUnit as GlucoseUnit;
    const scoped = row.mealContext in CONTEXT_LABEL ? row.mealContext : null;
    const since = new Date(row.measuredAt.getTime() - WINDOW_DAYS * DAY);
    const peers = await prisma.glucoseObservation.findMany({
      where: { userId, archivedAt: null, qualityStatus: { in: [...GLUCOSE_COUNTED_QUALITY] }, id: { not: row.id }, measuredAt: { gte: since, lt: row.measuredAt }, ...(scoped ? { mealContext: scoped } : {}) },
      orderBy: { measuredAt: "desc" },
      select: { id: true, valueMgDl: true, measuredAt: true },
    });
    const value = displayGlucose(row.valueMgDl, unit);
    const values = peers.map((p) => displayGlucose(p.valueMgDl, unit));
    const c = row.qualityStatus !== "needs_review" && !row.archivedAt ? compare(value, values) : null;
    const previous = peers[0];
    return {
      recordId: row.id,
      displayUnit: unit,
      value,
      mealContext: row.mealContext,
      comparison: c ? { ...c, basis: scoped ? "SAME_CONTEXT" : "ALL_CONTEXTS", windowDays: WINDOW_DAYS } : null,
      line: c ? glucoseLine(c, scoped, unit) : row.qualityStatus === "needs_review" ? "Catatan yang ditandai untuk ditinjau tidak dibandingkan." : insufficientLine(values.length),
      previous: previous ? { id: previous.id, value: displayGlucose(previous.valueMgDl, unit), ...localRecordTime(previous.measuredAt, timezone) } : null,
      alert: glucoseAlert(row.valueMgDl.toNumber()),
      neutralNote: "Perbandingan ini hanya dengan catatanmu sendiri dan bukan penilaian klinis.",
      computationVersion: CONTEXT_VERSION,
    };
  },

  async meal(userId: string, id: string) {
    await requireBoth(userId);
    const meal = await nutritionService.get(userId, id);
    const { timezone, glucoseUnit } = await preferencesService.get(userId);
    const unit = glucoseUnit as GlucoseUnit;
    const at = new Date(meal.consumedAt);
    const carbs = meal.totals.carbohydrates;
    const peers = await nutritionService.mealsBetween(userId, new Date(at.getTime() - WINDOW_DAYS * DAY), at, timezone);
    const peerCarbs = peers.filter((m) => m.id !== meal.id && m.category === meal.category && m.totals.carbohydrates.coverage === "COMPLETE" && m.totals.carbohydrates.value !== null).map((m) => m.totals.carbohydrates.value as number);
    const carbComparison = carbs.coverage === "COMPLETE" && carbs.value !== null ? compare(carbs.value, peerCarbs) : null;
    const readings = await prisma.glucoseObservation.findMany({
      where: { userId, archivedAt: null, qualityStatus: { in: [...GLUCOSE_COUNTED_QUALITY] }, measuredAt: { gte: new Date(at.getTime() - 90 * 60_000), lte: new Date(at.getTime() + 180 * 60_000) } },
      select: { id: true, measuredAt: true, valueMgDl: true, mealContext: true },
    });
    const pair = pairAround(at, readings.map((r) => ({ id: r.id, at: r.measuredAt, value: r.valueMgDl.toNumber(), mealContext: r.mealContext })));
    const view = (r: (typeof pair)["before"]) => (r ? { id: r.id, value: displayGlucose(new Prisma.Decimal(r.value), unit), minutesFromMeal: Math.round((r.at.getTime() - at.getTime()) / 60_000), ...localRecordTime(r.at, timezone) } : null);
    const before = view(pair.before);
    const after = view(pair.after);
    return {
      recordId: meal.id,
      category: meal.category,
      carbohydrates: { value: carbs.value, coverage: carbs.coverage },
      carbComparison: carbComparison ? { ...carbComparison, windowDays: WINDOW_DAYS } : null,
      carbLine: carbComparison ? carbLine(carbComparison, meal.category) : carbs.coverage !== "COMPLETE" ? "Karbohidrat belum lengkap untuk semua item, jadi tidak dibandingkan." : insufficientLine(peerCarbs.length),
      glucosePair: before || after ? { before, after, difference: before && after ? Math.round((after.value - before.value) * 10) / 10 : null, displayUnit: unit, note: NOT_CAUSAL } : null,
      pairHint: before || after ? null : "Tidak ada pengukuran glukosa dalam 90 menit sebelum sampai 3 jam setelah makan ini.",
      computationVersion: CONTEXT_VERSION,
    };
  },
};
