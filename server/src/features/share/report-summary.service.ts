import { prisma } from "../../infrastructure/database/prisma.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { clinicalService } from "../clinical/clinical.service.ts";
import { consentService } from "../consent/consent.service.ts";
import { deviceImportService } from "../devices/device-import.service.ts";
import { statisticsService } from "../insights/statistics.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";

export const REPORT_VERSION = "report-summary-v1";
export const REPORT_PERIODS = [14, 30, 90] as const;

export const reportSummaryService = {
  async build(userId: string, days: 14 | 30 | 90, now = new Date()) {
    await consentService.requireConsent(userId, "health_data_processing");
    await consentService.requireConsent(userId, "descriptive_summaries");
    const [{ timezone }, stats, clinical, steps, regimens, user, health] = await Promise.all([
      preferencesService.get(userId),
      statisticsService.get(userId, days, now),
      clinicalService.summary(userId, now),
      deviceImportService.steps(userId, days === 14 ? 14 : days === 30 ? 30 : 90, now),
      prisma.medicationRegimen.findMany({ where: { userId, status: "active" }, select: { name: true, strength: true, dosingInstructions: true }, orderBy: { createdAt: "asc" } }),
      prisma.users.findUniqueOrThrow({ where: { id: userId }, select: { name: true } }),
      prisma.healthProfile.findUnique({ where: { userId }, select: { diabetesType: true, diagnosedYear: true } }),
    ]);
    return {
      version: REPORT_VERSION,
      generatedAt: now.toISOString(),
      generatedLocal: localRecordTime(now, timezone),
      timezone,
      person: { name: user.name, diabetesType: health?.diabetesType ?? null, diagnosedYear: health?.diagnosedYear ?? null },
      period: stats.period,
      days,
      glucoseUnit: stats.glucoseUnit,
      statistics: stats.statistics
        .filter((s) => s.domain !== "nutrition" || s.id.startsWith("nutrition.carbohydrates"))
        .map((s) => ({ id: s.id, domain: s.domain, label: s.label, value: s.value, unit: s.unit, state: s.state, sampleCount: s.sampleCount, sampleUnit: s.sampleUnit, coverage: s.coverage, limitations: s.limitations })),
      steps: { daysWithData: steps.daysWithData, medianSteps: steps.medianSteps },
      vitals: clinical.vitals.filter((v) => v.latest).map((v) => ({ label: v.label, value: v.latest!.display, date: v.latest!.localDate, change: v.change })),
      labs: clinical.labs.filter((l) => l.latest).map((l) => ({ label: l.label, value: l.latest!.display, date: l.latest!.sampledAt, change: l.change })),
      medications: regimens.map((r) => ({ name: r.name, strength: r.strength, instructions: r.dosingInstructions })),
      disclaimer: "Ringkasan deskriptif dari catatan yang dimasukkan pengguna sendiri atau dari perangkatnya. Bukan hasil pemeriksaan, bukan diagnosis, dan tidak memuat prediksi. Data yang tidak dicatat tidak tampil.",
    };
  },
};

export type ReportSummary = Awaited<ReturnType<typeof reportSummaryService.build>>;
