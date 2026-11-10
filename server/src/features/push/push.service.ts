import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { notFound } from "../../shared/errors/app-error.ts";
import { consentService } from "../consent/consent.service.ts";
import type { PushRegister } from "./push.schema.ts";

export const MAX_ACTIVE_DEVICES = 5;
const requireHealth = (userId: string) => consentService.requireConsent(userId, "health_data_processing");
type Row = NonNullable<Awaited<ReturnType<typeof prisma.pushDevice.findFirst>>>;

/** Token tidak pernah dikembalikan utuh; hanya ujungnya agar pengguna bisa membedakan perangkat. */
const view = (d: Row) => ({
  id: d.id,
  platform: d.platform,
  appVersion: d.appVersion,
  active: d.active,
  tokenHint: `…${d.token.slice(-6)}`,
  lastSeenAt: d.lastSeenAt.toISOString(),
  createdAt: d.createdAt.toISOString(),
});

export const pushService = {
  /**
   * Mendaftarkan perangkat atas permintaan eksplisit pengguna. Token yang sama menjadi milik akun yang terakhir
   * mendaftarkannya (perangkat berpindah akun); sisa jatah dijaga dengan menonaktifkan perangkat terlama.
   */
  async register(userId: string, input: PushRegister) {
    await requireHealth(userId);
    return prisma.$transaction(async (tx) => {
      const existing = await tx.pushDevice.findUnique({ where: { token: input.token } });
      const saved = existing
        ? await tx.pushDevice.update({ where: { id: existing.id }, data: { userId, platform: input.platform, appVersion: input.appVersion ?? null, active: true, lastError: null, lastSeenAt: new Date() } })
        : await tx.pushDevice.create({ data: { userId, token: input.token, platform: input.platform, appVersion: input.appVersion ?? null } });
      const active = await tx.pushDevice.findMany({ where: { userId, active: true }, orderBy: [{ lastSeenAt: "desc" }, { id: "asc" }] });
      const overflow = active.slice(MAX_ACTIVE_DEVICES).map((d) => d.id);
      if (overflow.length) await tx.pushDevice.updateMany({ where: { id: { in: overflow } }, data: { active: false, lastError: "SUPERSEDED" } });
      await recordAudit(tx, { userId, eventType: "push_device_registered", metadata: { deviceId: saved.id, reassigned: Boolean(existing && existing.userId !== userId) } });
      return { created: !existing, item: view(saved) };
    });
  },

  async list(userId: string) {
    await requireHealth(userId);
    const rows = await prisma.pushDevice.findMany({ where: { userId, active: true }, orderBy: { lastSeenAt: "desc" } });
    return { items: rows.map(view), limit: MAX_ACTIVE_DEVICES };
  },

  /** Mencabut perangkat: token dihapus dari basis data (bukan hanya dinonaktifkan). Tidak butuh consent: selalu boleh berhenti. */
  async unregister(userId: string, id: string) {
    const row = await prisma.pushDevice.findFirst({ where: { id, userId } });
    if (!row) throw notFound("DEVICE_NOT_FOUND", "Perangkat tidak ditemukan.");
    await prisma.$transaction(async (tx) => {
      await tx.pushDevice.delete({ where: { id } });
      await recordAudit(tx, { userId, eventType: "push_device_removed", metadata: { deviceId: id } });
    });
    return { removed: true };
  },
};
