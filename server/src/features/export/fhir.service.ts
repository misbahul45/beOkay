import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { AppError } from "../../shared/errors/app-error.ts";
import { rateWindow } from "../../shared/http/rate-window.ts";
import { GLUCOSE_COUNTED_QUALITY } from "../glucose/glucose.model.ts";
import { buildFhirBundle } from "./fhir.model.ts";

const calls = rateWindow(60 * 60_000, 5);

export const fhirExportService = {
  async build(userId: string, now = new Date()) {
    if (calls.full(userId, now.getTime())) throw new AppError(429, "EXPORT_RATE_LIMITED", "Terlalu sering mengunduh data. Coba lagi dalam satu jam.");
    calls.record(userId, now.getTime());
    const live = { userId, archivedAt: null };
    const [user, glucose, labs, vitals, steps] = await Promise.all([
      prisma.users.findUniqueOrThrow({ where: { id: userId }, select: { id: true, name: true } }),
      prisma.glucoseObservation.findMany({ where: { ...live, qualityStatus: { in: [...GLUCOSE_COUNTED_QUALITY] } }, orderBy: { measuredAt: "asc" }, take: 20_000 }),
      prisma.labResult.findMany({ where: live, orderBy: { sampledAt: "asc" } }),
      prisma.vitalMeasurement.findMany({ where: live, orderBy: { measuredAt: "asc" } }),
      prisma.dailySteps.findMany({ where: { userId }, orderBy: { localDate: "asc" } }),
    ]);
    const bundle = buildFhirBundle({
      patientId: user.id,
      name: user.name,
      generatedAt: now,
      glucose: glucose.map((g) => ({ id: g.id, valueMgDl: g.valueMgDl.toNumber(), measuredAt: g.measuredAt, mealContext: g.mealContext, source: g.source })),
      labs: labs.map((l) => ({ id: l.id, test: l.test, value: l.value.toNumber(), unit: l.unit, sampledAt: l.sampledAt })),
      vitals: vitals.map((v) => ({ id: v.id, kind: v.kind, value: v.value.toNumber(), value2: v.value2?.toNumber() ?? null, unit: v.unit, measuredAt: v.measuredAt })),
      steps: steps.map((s) => ({ id: s.id, localDate: s.localDate, steps: s.steps })),
    });
    await prisma.$transaction(async (tx) => recordAudit(tx, { userId, eventType: "data_exported_fhir", metadata: { resources: bundle.entry.length } }));
    return bundle;
  },
};
