import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { realtime } from "../../infrastructure/realtime/realtime.ts";
import { notFound } from "../../shared/errors/app-error.ts";
import { logEvent } from "../../shared/http/logger.ts";
import { consentService } from "../consent/consent.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import type { PushMessage, PushReceipt } from "../push/fcm.client.ts";
import { upcomingOccurrences, type ReminderKind } from "../reminders/reminders.model.ts";

export const NOTIFICATION_KINDS = ["REMINDER", "COACHING", "REFLECTION", "CHALLENGE", "RECOGNITION"] as const;
export type NotificationKind = (typeof NOTIFICATION_KINDS)[number];
export type NotificationAction = "OPEN_HOME" | "OPEN_LOG" | "OPEN_COACHING" | "OPEN_REFLECTION" | "OPEN_CHALLENGE" | "OPEN_COMMUNITY" | "OPEN_RECOGNITIONS" | "OPEN_REMINDERS" | "OPEN_GOALS" | "OPEN_MEDICATIONS";
export type NewNotification = { kind: NotificationKind; title: string; body: string; action: NotificationAction; refId?: string | null; dedupeKey: string };
type Sender = { configured: boolean; send(message: PushMessage): Promise<PushReceipt> };

export const REMINDER_LOOKBACK_MS = 3 * 60_000;
const LOCK_SCREEN: Record<NotificationKind, { title: string; body: string }> = {
  REMINDER: { title: "Pengingat beOkay", body: "Buka beOkay untuk mencatat." },
  COACHING: { title: "beOkay", body: "Ada rencana kecil untukmu hari ini." },
  REFLECTION: { title: "beOkay", body: "Refleksi mingguanmu siap." },
  CHALLENGE: { title: "beOkay", body: "Ada kabar dari tantanganmu." },
  RECOGNITION: { title: "beOkay", body: "Ada pencapaian baru untukmu." },
};
const REMINDER_TEXT: Record<ReminderKind, { body: string; action: NotificationAction }> = {
  meal: { body: "Waktunya mencatat makan.", action: "OPEN_LOG" },
  activity: { body: "Waktunya bergerak sebentar, lalu catat.", action: "OPEN_LOG" },
  glucose: { body: "Waktunya mencatat pengukuran glukosa.", action: "OPEN_LOG" },
  medication: { body: "Cek jadwal obatmu.", action: "OPEN_MEDICATIONS" },
  goal: { body: "Cek tujuanmu hari ini.", action: "OPEN_GOALS" },
  custom: { body: "Pengingat yang kamu buat.", action: "OPEN_REMINDERS" },
};

export function reminderTarget(kind: ReminderKind, reminderId: string, coachingActionId?: string | null): { action: NotificationAction; refId: string } {
  if (coachingActionId) return { action: "OPEN_COACHING", refId: coachingActionId };
  return { action: (REMINDER_TEXT[kind] ?? REMINDER_TEXT.custom).action, refId: reminderId };
}

export function pushAllowed(pref: { pushEnabled: boolean; mutedKinds: string[] } | null, kind: NotificationKind) {
  return !pref || (pref.pushEnabled && !pref.mutedKinds.includes(kind));
}

let sender: Sender | null = null;
const isUnique = (e: unknown) => e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002";
type Row = NonNullable<Awaited<ReturnType<typeof prisma.notification.findFirst>>>;

export const notificationView = (n: Row) => ({
  id: n.id,
  kind: n.kind,
  title: n.title,
  body: n.body,
  action: n.action,
  refId: n.refId,
  read: n.readAt !== null,
  createdAt: n.createdAt.toISOString(),
});

async function preferenceOf(userId: string) {
  return (await prisma.notificationPreference.findUnique({ where: { userId } })) ?? { userId, pushEnabled: true, mutedKinds: [] as string[] };
}

async function unread(userId: string) {
  return prisma.notification.count({ where: { userId, readAt: null } });
}

async function push(userId: string, row: Row) {
  if (!sender?.configured) return;
  const devices = await prisma.pushDevice.findMany({ where: { userId, active: true } });
  if (!devices.length) return;
  const text = LOCK_SCREEN[row.kind as NotificationKind];
  let sent = false;
  for (const d of devices) {
    try {
      const r = await sender.send({ token: d.token, title: text.title, body: text.body, data: { type: row.kind, notificationId: row.id, action: row.action, refId: row.refId ?? "" }, collapseKey: `${row.kind}-${row.refId ?? row.id}`, ttlSeconds: 3600 });
      if (r.status === "sent") sent = true;
      if (r.shouldDeactivate) await prisma.pushDevice.update({ where: { id: d.id }, data: { active: false, lastError: r.errorCode ?? "INVALID_TOKEN" } });
    } catch (e) {
      logEvent("error", "notification_push_failed", { name: e instanceof Error ? e.name : "unknown" });
    }
  }
  if (sent) await prisma.notification.update({ where: { id: row.id }, data: { pushedAt: new Date() } });
}

export const notificationService = {
  setPushSender(s: Sender) {
    sender = s;
  },

  async notify(userId: string, n: NewNotification, opts: { push?: boolean } = {}) {
    const pref = await preferenceOf(userId);
    if (pref.mutedKinds.includes(n.kind)) return null;
    let row: Row;
    try {
      row = await prisma.notification.create({ data: { userId, kind: n.kind, title: n.title.slice(0, 80), body: n.body.slice(0, 240), action: n.action, refId: n.refId ?? null, dedupeKey: n.dedupeKey } });
    } catch (e) {
      if (isUnique(e)) return null;
      throw e;
    }
    realtime.toUser(userId, { type: "notification", item: notificationView(row), unread: await unread(userId) });
    if (opts.push !== false && pref.pushEnabled) void push(userId, row).catch(() => {});
    return notificationView(row);
  },

  async list(userId: string, q: { cursor?: string; limit: number }) {
    const anchor = q.cursor ? await prisma.notification.findFirst({ where: { id: q.cursor, userId } }) : null;
    if (q.cursor && !anchor) throw notFound("CURSOR_NOT_FOUND", "Cursor tidak ditemukan.");
    const rows = await prisma.notification.findMany({
      where: { userId, ...(anchor ? { OR: [{ createdAt: { lt: anchor.createdAt } }, { createdAt: anchor.createdAt, id: { lt: anchor.id } }] } : {}) },
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: q.limit + 1,
    });
    const page = rows.slice(0, q.limit);
    return { items: page.map(notificationView), nextCursor: rows.length > q.limit ? page.at(-1)!.id : null, unread: await unread(userId) };
  },

  async unreadCount(userId: string) {
    return { unread: await unread(userId) };
  },

  async markRead(userId: string, id: string) {
    const row = await prisma.notification.findFirst({ where: { id, userId } });
    if (!row) throw notFound("NOTIFICATION_NOT_FOUND", "Notifikasi tidak ditemukan.");
    if (!row.readAt) await prisma.notification.updateMany({ where: { id, userId, readAt: null }, data: { readAt: new Date() } });
    const count = await unread(userId);
    realtime.toUser(userId, { type: "notifications.read", ids: [id], unread: count });
    return { id, read: true, unread: count };
  },

  async markAllRead(userId: string) {
    const r = await prisma.notification.updateMany({ where: { userId, readAt: null }, data: { readAt: new Date() } });
    realtime.toUser(userId, { type: "notifications.read", all: true, unread: 0 });
    return { updated: r.count, unread: 0 };
  },

  async getPreferences(userId: string) {
    const p = await preferenceOf(userId);
    return { pushEnabled: p.pushEnabled, mutedKinds: p.mutedKinds, kinds: NOTIFICATION_KINDS, pushConfigured: Boolean(sender?.configured), devices: await prisma.pushDevice.count({ where: { userId, active: true } }) };
  },

  async updatePreferences(userId: string, input: { pushEnabled?: boolean; mutedKinds?: NotificationKind[] }) {
    const data = { ...(input.pushEnabled !== undefined ? { pushEnabled: input.pushEnabled } : {}), ...(input.mutedKinds ? { mutedKinds: [...new Set(input.mutedKinds)] } : {}) };
    await prisma.notificationPreference.upsert({ where: { userId }, create: { userId, ...data }, update: data });
    return this.getPreferences(userId);
  },

  async notifyDueReminders(now = new Date()) {
    const users = await prisma.reminder.findMany({ where: { enabled: true, archivedAt: null }, distinct: ["userId"], select: { userId: true }, take: 2000 });
    let created = 0;
    for (const { userId } of users) {
      try {
        await consentService.requireConsent(userId, "health_data_processing");
      } catch {
        continue;
      }
      const reminders = await prisma.reminder.findMany({ where: { userId, enabled: true, archivedAt: null }, include: { coachingActions: { where: { status: "ACCEPTED" }, select: { id: true } } } });
      const { timezone } = await preferencesService.get(userId);
      const due = upcomingOccurrences(
        reminders.map((r) => ({ id: r.id, kind: r.kind as ReminderKind, localTime: r.localTime, daysOfWeek: r.daysOfWeek, enabled: r.enabled })),
        timezone,
        new Date(now.getTime() - REMINDER_LOOKBACK_MS),
        1,
      ).filter((o) => o.at.getTime() <= now.getTime());
      for (const occ of due) {
        const r = reminders.find((x) => x.id === occ.reminderId)!;
        const text = REMINDER_TEXT[r.kind as ReminderKind] ?? REMINDER_TEXT.custom;
        const coaching = r.coachingActions[0];
        const target = reminderTarget(r.kind as ReminderKind, r.id, coaching?.id);
        const made = await this.notify(userId, { kind: "REMINDER", title: r.title, body: coaching ? "Rencana kecilmu hari ini." : text.body, action: target.action, refId: target.refId, dedupeKey: `reminder:${r.id}:${occ.at.toISOString()}` }, { push: false });
        if (made) created++;
      }
    }
    return { users: users.length, created };
  },
};

export function startNotificationWorker(intervalMs = 30_000, extra: () => Promise<void> = async () => {}) {
  let running = false;
  const tick = async () => {
    if (running) return;
    running = true;
    try {
      const r = await notificationService.notifyDueReminders();
      if (r.created > 0) logEvent("info", "reminder_notifications", r);
      await extra();
    } catch (e) {
      logEvent("error", "notification_worker_failed", { name: e instanceof Error ? e.name : "unknown" });
    } finally {
      running = false;
    }
  };
  const timer = setInterval(tick, intervalMs);
  return { stop: () => clearInterval(timer) };
}
