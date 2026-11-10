import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { AppError } from "../../shared/errors/app-error.ts";

export const EXPORT_FORMAT_VERSION = "beokay-export-v1";
const WINDOW_MS = 60 * 60_000;
const MAX_EXPORTS = 5;
const calls = new Map<string, number[]>();

/** Bidang internal yang tidak berguna bagi pengguna dan tidak boleh keluar (hash idempotensi, rahasia). */
const INTERNAL_KEYS = new Set(["createHash", "payloadHash"]);
export function stripInternal<T>(value: T): T {
  if (Array.isArray(value)) return value.map(stripInternal) as T;
  if (value && typeof value === "object" && !(value instanceof Date) && !("toFixed" in (value as object))) {
    return Object.fromEntries(Object.entries(value as object).filter(([k]) => !INTERNAL_KEYS.has(k)).map(([k, v]) => [k, stripInternal(v)])) as T;
  }
  return value;
}

export const exportService = {
  /**
   * Ekspor seluruh data milik sendiri. Hak akses/portabilitas data tidak bergantung pada consent pemrosesan:
   * pengguna yang menarik consent tetap bisa mengunduh datanya. Sesi, akun (kata sandi), token, dan hash internal tidak diekspor.
   */
  async build(userId: string, now = new Date()) {
    const t = now.getTime();
    const recent = (calls.get(userId) ?? []).filter((x) => t - x < WINDOW_MS);
    if (recent.length >= MAX_EXPORTS) {
      calls.set(userId, recent);
      throw new AppError(429, "EXPORT_RATE_LIMITED", "Terlalu sering mengunduh data. Coba lagi dalam satu jam.");
    }
    calls.set(userId, [...recent, t]);

    const own = { userId };
    const [user, profile, healthProfile, settings, onboarding, consents, foods, portionMeasures, meals, glucose, activities, regimens, goals, revisions, foodPreferences, reminders, audit] = await prisma.$transaction(
      [
        prisma.users.findUniqueOrThrow({ where: { id: userId }, select: { id: true, name: true, email: true, emailVerified: true, createdAt: true } }),
        prisma.userProfile.findUnique({ where: own }),
        prisma.healthProfile.findUnique({ where: own }),
        prisma.userSettings.findUnique({ where: own }),
        prisma.onboardingProgress.findUnique({ where: own }),
        prisma.consentRecord.findMany({ where: own, orderBy: { grantedAt: "asc" } }),
        prisma.foodCatalog.findMany({ where: own, orderBy: { createdAt: "asc" } }),
        prisma.foodPortionMeasure.findMany({ where: own, orderBy: { createdAt: "asc" } }),
        prisma.mealLog.findMany({ where: own, include: { items: true }, orderBy: { consumedAt: "asc" } }),
        prisma.glucoseObservation.findMany({ where: own, orderBy: { measuredAt: "asc" } }),
        prisma.activitySession.findMany({ where: own, orderBy: { startedAt: "asc" } }),
        prisma.medicationRegimen.findMany({ where: own, include: { schedules: true, intakes: true }, orderBy: { createdAt: "asc" } }),
        prisma.behaviorGoal.findMany({ where: own, include: { checkins: true }, orderBy: { createdAt: "asc" } }),
        prisma.recordRevision.findMany({ where: own, orderBy: { createdAt: "asc" } }),
        prisma.foodPreference.findMany({ where: own, orderBy: { createdAt: "asc" } }),
        prisma.reminder.findMany({ where: own, orderBy: { createdAt: "asc" } }),
        prisma.auditEvent.findMany({ where: own, orderBy: { occurredAt: "asc" }, take: 5000 }),
      ],
      { isolationLevel: "RepeatableRead" },
    );

    const data = stripInternal({
      account: user,
      profile,
      healthProfile,
      settings,
      onboarding,
      consents,
      foods,
      foodPortionMeasures: portionMeasures,
      meals,
      glucoseObservations: glucose,
      activitySessions: activities,
      medicationRegimens: regimens,
      goals,
      recordRevisions: revisions,
      foodPreferences,
      reminders,
      auditEvents: audit,
    });
    const counts = Object.fromEntries(Object.entries(data).map(([k, v]) => [k, Array.isArray(v) ? v.length : v ? 1 : 0]));
    await recordAudit(prisma, { userId, eventType: "export_requested", metadata: { format: EXPORT_FORMAT_VERSION } });
    return {
      format: EXPORT_FORMAT_VERSION,
      generatedAt: now.toISOString(),
      notice: "Berkas ini berisi data kesehatanmu. Simpan di tempat yang aman. Ringkasan turunan, sesi, dan kata sandi tidak disertakan.",
      counts,
      data,
    };
  },
};
