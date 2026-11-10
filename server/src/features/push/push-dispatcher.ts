import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { logEvent } from "../../shared/http/logger.ts";
import { consentService } from "../consent/consent.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { lockScreenText, upcomingOccurrences, type ReminderKind } from "../reminders/reminders.model.ts";
import type { PushMessage, PushReceipt } from "./fcm.client.ts";

type Sender = { configured: boolean; send(message: PushMessage): Promise<PushReceipt> };

/** Pengingat yang terlambat lebih dari ini tidak dikirim (misalnya server mati): pengingat basi lebih buruk daripada tidak ada. */
export const LOOKBACK_MS = 3 * 60_000;
const isUnique = (e: unknown) => e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002";

export type DispatchStats = { users: number; due: number; sent: number; failed: number; deactivated: number; skippedNoConsent: number };

/**
 * Satu putaran pengiriman. Idempoten: buku besar `push_deliveries` unik per (pengingat, perangkat, waktu jadwal), jadi
 * putaran ganda atau beberapa instans tidak mengirim dua kali. Isi pesan generik (tanpa judul pengguna, nama obat, atau angka).
 */
export async function dispatchDueReminders(sender: Sender, now = new Date()): Promise<DispatchStats> {
  const stats: DispatchStats = { users: 0, due: 0, sent: 0, failed: 0, deactivated: 0, skippedNoConsent: 0 };
  if (!sender.configured) return stats;
  const devices = await prisma.pushDevice.findMany({ where: { active: true } });
  const byUser = new Map<string, typeof devices>();
  for (const d of devices) byUser.set(d.userId, [...(byUser.get(d.userId) ?? []), d]);

  for (const [userId, userDevices] of byUser) {
    stats.users++;
    try {
      await consentService.requireConsent(userId, "health_data_processing");
    } catch {
      stats.skippedNoConsent++; // consent ditarik: tidak ada push, meski token masih tersimpan
      continue;
    }
    const reminders = await prisma.reminder.findMany({ where: { userId, enabled: true, archivedAt: null } });
    if (!reminders.length) continue;
    const { timezone } = await preferencesService.get(userId);
    const from = new Date(now.getTime() - LOOKBACK_MS);
    const due = upcomingOccurrences(
      reminders.map((r) => ({ id: r.id, kind: r.kind as ReminderKind, localTime: r.localTime, daysOfWeek: r.daysOfWeek, enabled: r.enabled })),
      timezone,
      from,
      1,
    ).filter((o) => o.at.getTime() <= now.getTime());
    const kindOf = new Map(reminders.map((r) => [r.id, r.kind as ReminderKind]));

    for (const occ of due) {
      stats.due++;
      for (const device of userDevices) {
        let ledgerId: string;
        try {
          const row = await prisma.pushDelivery.create({ data: { userId, reminderId: occ.reminderId, deviceId: device.id, scheduledAt: occ.at, status: "pending" } });
          ledgerId = row.id;
        } catch (e) {
          if (isUnique(e)) continue; // sudah ditangani putaran/instans lain
          throw e;
        }
        const text = lockScreenText(kindOf.get(occ.reminderId)!);
        const receipt = await sender.send({ token: device.token, title: text.title, body: text.body, data: { type: "reminder" }, collapseKey: `reminder-${occ.reminderId}`, ttlSeconds: 1800 });
        await prisma.pushDelivery.update({ where: { id: ledgerId }, data: { status: receipt.status, providerMessageId: receipt.providerMessageId, errorCode: receipt.errorCode, attemptedAt: new Date() } });
        if (receipt.status === "sent") stats.sent++;
        else stats.failed++;
        if (receipt.shouldDeactivate) {
          await prisma.pushDevice.update({ where: { id: device.id }, data: { active: false, lastError: receipt.errorCode ?? "INVALID_TOKEN" } });
          stats.deactivated++;
        }
      }
    }
  }
  if (stats.due > 0) logEvent("info", "push_dispatch", { ...stats });
  return stats;
}

/** Pemicu berkala. Satu putaran berjalan pada satu waktu; kegagalan satu putaran tidak menghentikan pemicu. */
export function startPushDispatcher(sender: Sender, intervalMs = 30_000) {
  if (!sender.configured) return { stop() {} };
  let running = false;
  const timer = setInterval(async () => {
    if (running) return;
    running = true;
    try {
      await dispatchDueReminders(sender);
    } catch (e) {
      logEvent("error", "push_dispatch_failed", { name: e instanceof Error ? e.name : "unknown" });
    } finally {
      running = false;
    }
  }, intervalMs);
  return { stop: () => clearInterval(timer) };
}
