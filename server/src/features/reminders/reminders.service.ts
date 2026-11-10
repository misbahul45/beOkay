import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { conflict, notFound, unprocessable } from "../../shared/errors/app-error.ts";
import { consentService } from "../consent/consent.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { lockScreenText, nextOccurrence, upcomingOccurrences, type ReminderKind, type ReminderRule } from "./reminders.model.ts";
import type { ReminderCreate, ReminderPatch } from "./reminders.schema.ts";

export const MAX_ACTIVE_REMINDERS = 20;
const requireHealth = (userId: string) => consentService.requireConsent(userId, "health_data_processing");
type Row = NonNullable<Awaited<ReturnType<typeof prisma.reminder.findFirst>>>;
const rule = (r: Row): ReminderRule => ({ id: r.id, kind: r.kind as ReminderKind, localTime: r.localTime, daysOfWeek: r.daysOfWeek, enabled: r.enabled });
const view = (r: Row, timezone: string, now: Date) => ({
  id: r.id,
  kind: r.kind as ReminderKind,
  title: r.title,
  localTime: r.localTime,
  daysOfWeek: r.daysOfWeek,
  enabled: r.enabled,
  version: r.version,
  archivedAt: r.archivedAt?.toISOString() ?? null,
  nextAt: r.enabled && !r.archivedAt ? (nextOccurrence(rule(r), timezone, now)?.at.toISOString() ?? null) : null,
  lockScreen: lockScreenText(r.kind as ReminderKind),
  timezone,
});

export const remindersService = {
  async list(userId: string, now = new Date()) {
    await requireHealth(userId);
    const { timezone } = await preferencesService.get(userId);
    const rows = await prisma.reminder.findMany({ where: { userId, archivedAt: null }, orderBy: [{ localTime: "asc" }, { id: "asc" }] });
    return { items: rows.map((r) => view(r, timezone, now)), limit: MAX_ACTIVE_REMINDERS };
  },

  async create(userId: string, input: ReminderCreate, now = new Date()) {
    await requireHealth(userId);
    const { timezone } = await preferencesService.get(userId);
    return prisma.$transaction(async (tx) => {
      const active = await tx.reminder.count({ where: { userId, archivedAt: null } });
      if (active >= MAX_ACTIVE_REMINDERS) throw unprocessable("REMINDER_LIMIT", `Maksimal ${MAX_ACTIVE_REMINDERS} pengingat aktif.`);
      const saved = await tx.reminder.create({ data: { userId, ...input } });
      await recordAudit(tx, { userId, eventType: "reminder_created", metadata: { recordId: saved.id, kind: saved.kind } });
      return view(saved, timezone, now);
    });
  },

  async update(userId: string, id: string, input: ReminderPatch, now = new Date()) {
    await requireHealth(userId);
    const { timezone } = await preferencesService.get(userId);
    return prisma.$transaction(async (tx) => {
      const row = await tx.reminder.findFirst({ where: { id, userId } });
      if (!row) throw notFound("REMINDER_NOT_FOUND", "Pengingat tidak ditemukan.");
      if (row.version !== input.expectedVersion) throw conflict("VERSION_CONFLICT", "Pengingat sudah berubah. Muat ulang lalu coba lagi.", { currentVersion: row.version });
      if (input.archived === false && row.archivedAt && (await tx.reminder.count({ where: { userId, archivedAt: null } })) >= MAX_ACTIVE_REMINDERS)
        throw unprocessable("REMINDER_LIMIT", `Maksimal ${MAX_ACTIVE_REMINDERS} pengingat aktif.`);
      const saved = await tx.reminder.update({
        where: { id },
        data: {
          ...(input.title !== undefined ? { title: input.title } : {}),
          ...(input.localTime !== undefined ? { localTime: input.localTime } : {}),
          ...(input.daysOfWeek !== undefined ? { daysOfWeek: input.daysOfWeek } : {}),
          ...(input.enabled !== undefined ? { enabled: input.enabled } : {}),
          ...(input.archived !== undefined ? { archivedAt: input.archived ? new Date() : null } : {}),
          version: { increment: 1 },
        },
      });
      await recordAudit(tx, { userId, eventType: "reminder_updated", metadata: { recordId: id } });
      return view(saved, timezone, now);
    });
  },

  /** Kejadian untuk dijadwalkan sebagai notifikasi lokal. Tidak ada pengiriman dari server. */
  async upcoming(userId: string, days: number, now = new Date()) {
    await requireHealth(userId);
    const { timezone } = await preferencesService.get(userId);
    const rows = await prisma.reminder.findMany({ where: { userId, archivedAt: null, enabled: true } });
    const byId = new Map(rows.map((r) => [r.id, r]));
    const occurrences = upcomingOccurrences(rows.map(rule), timezone, now, days);
    return {
      timezone,
      generatedAt: now.toISOString(),
      items: occurrences.map((o) => ({
        reminderId: o.reminderId,
        at: o.at.toISOString(),
        localDate: o.localDate,
        localTime: o.localTime,
        ...lockScreenText(byId.get(o.reminderId)!.kind as ReminderKind),
      })),
    };
  },
};
