import { createHash } from "node:crypto";
import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { conflict, notFound, unprocessable } from "../../shared/errors/app-error.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { consentService } from "../consent/consent.service.ts";
import { emitRecordEvent } from "../events/record-events.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { occurrencesFor, summarizeOccurrences, zonedToUtc } from "./medication.model.ts";
import type { IntakeInput, IntakePatch, RegimenInput, RegimenPatch, ScheduleInput, SchedulePatch } from "./medication.schema.ts";
import { medicationRepository as repo } from "./medication.repository.ts";

const day = (d: Date | null) => d?.toISOString().slice(0, 10) ?? null;
const sha = (v: unknown) => createHash("sha256").update(JSON.stringify(v)).digest("hex");
const asDate = (d: string | null | undefined) => (d ? new Date(d + "T00:00:00Z") : d === null ? null : undefined);
type Regimen = NonNullable<Awaited<ReturnType<typeof repo.regimen>>>;
type Schedule = NonNullable<Awaited<ReturnType<typeof repo.schedule>>>;
type Intake = NonNullable<Awaited<ReturnType<typeof repo.intake>>>;

const regimenView = (r: Regimen) => ({ id: r.id, name: r.name, strength: r.strength, dosageForm: r.dosageForm, dosingInstructions: r.dosingInstructions, instructionSource: r.instructionSource, startDate: day(r.startDate), endDate: day(r.endDate), status: r.status, version: r.version, createdAt: r.createdAt.toISOString(), updatedAt: r.updatedAt.toISOString() });
const scheduleView = (s: Schedule) => ({ id: s.id, regimenId: s.regimenId, localTime: s.localTime, timezone: s.timezone, daysOfWeek: s.daysOfWeek, enabled: s.enabled, effectiveFrom: day(s.effectiveFrom), disabledAt: s.disabledAt?.toISOString() ?? null, createdAt: s.createdAt.toISOString() });
function intakeView(i: Intake, timezone: string) {
  const local = localRecordTime(i.eventAt, timezone);
  return { id: i.id, regimenId: i.regimenId, scheduleId: i.scheduleId, scheduledAt: i.scheduledAt?.toISOString() ?? null, takenAt: i.takenAt?.toISOString() ?? null, eventAt: i.eventAt.toISOString(), status: i.status, medicationSnapshot: i.medicationSnapshot, notes: i.notes, version: i.version, archivedAt: i.archivedAt?.toISOString() ?? null, createdAt: i.createdAt.toISOString(), updatedAt: i.updatedAt.toISOString(), ...local };
}
const requireHealth = (userId: string) => consentService.requireConsent(userId, "health_data_processing");
const snapshotOf = (r: Regimen, localTime?: string) => ({ name: r.name, strength: r.strength, dosageForm: r.dosageForm, dosingInstructions: r.dosingInstructions, instructionSource: r.instructionSource, regimenVersion: r.version, ...(localTime ? { scheduleLocalTime: localTime } : {}) });
const isUnique = (e: unknown) => e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002";
const needRegimen = async (userId: string, id: string, db?: Prisma.TransactionClient) => {
  const r = await repo.regimen(userId, id, db);
  if (!r) throw notFound("MEDICATION_NOT_FOUND", "Obat tidak ditemukan.");
  return r;
};

export const medicationService = {
  async create(userId: string, input: RegimenInput) {
    await requireHealth(userId);
    const hash = sha(input);
    try {
      const row = await prisma.$transaction(async (tx) => {
        const old = await repo.regimen(userId, input.id, tx);
        if (old) {
          if (old.createHash !== hash) throw conflict("IDEMPOTENCY_CONFLICT", "ID obat sudah digunakan dengan isi berbeda.");
          return old;
        }
        const saved = await tx.medicationRegimen.create({ data: { ...input, startDate: asDate(input.startDate) ?? null, endDate: asDate(input.endDate) ?? null, userId, createHash: hash } });
        await recordAudit(tx, { userId, eventType: "medication_regimen_created", metadata: { recordId: saved.id } });
        return saved;
      });
      return regimenView(row);
    } catch (e) {
      if (isUnique(e)) {
        const old = await repo.regimen(userId, input.id);
        if (old?.createHash === hash) return regimenView(old);
        throw conflict("IDEMPOTENCY_CONFLICT", "ID obat sudah digunakan.");
      }
      throw e;
    }
  },
  async list(userId: string, q: { cursor?: string; limit: number; status?: string }) {
    await requireHealth(userId);
    const anchor = q.cursor ? await repo.regimen(userId, q.cursor) : null;
    if (q.cursor && !anchor) throw notFound("CURSOR_NOT_FOUND", "Cursor tidak ditemukan.");
    const rows = await prisma.medicationRegimen.findMany({
      where: { userId, ...(q.status ? { status: q.status } : {}), ...(anchor ? { OR: [{ createdAt: { lt: anchor.createdAt } }, { createdAt: anchor.createdAt, id: { lt: anchor.id } }] } : {}) },
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: q.limit + 1,
      include: { schedules: { where: { enabled: true }, orderBy: { localTime: "asc" } } },
    });
    const page = rows.slice(0, q.limit);
    return { items: page.map((r) => ({ ...regimenView(r), schedules: r.schedules.map(scheduleView) })), nextCursor: rows.length > q.limit ? page.at(-1)!.id : null };
  },
  async get(userId: string, id: string) {
    await requireHealth(userId);
    const r = await needRegimen(userId, id);
    const schedules = await prisma.medicationSchedule.findMany({ where: { userId, regimenId: id }, orderBy: [{ enabled: "desc" }, { localTime: "asc" }] });
    return { ...regimenView(r), schedules: schedules.map(scheduleView) };
  },
  async update(userId: string, id: string, input: RegimenPatch) {
    await requireHealth(userId);
    const row = await prisma.$transaction(async (tx) => {
      const old = await needRegimen(userId, id, tx);
      if (old.version !== input.expectedVersion) throw conflict("VERSION_CONFLICT", "Obat berubah. Muat ulang sebelum mengoreksi.");
      const { expectedVersion, reason, startDate, endDate, ...fields } = input;
      const next = { startDate: startDate === undefined ? old.startDate : asDate(startDate)!, endDate: endDate === undefined ? old.endDate : asDate(endDate)! };
      if (next.startDate && next.endDate && next.endDate < next.startDate) throw unprocessable("INVALID_DATE_RANGE", "Tanggal selesai mendahului tanggal mulai.");
      const changed = await tx.medicationRegimen.updateMany({ where: { id, userId, version: expectedVersion }, data: { ...fields, ...(startDate !== undefined ? { startDate: next.startDate } : {}), ...(endDate !== undefined ? { endDate: next.endDate } : {}), version: { increment: 1 } } });
      if (changed.count !== 1) throw conflict("VERSION_CONFLICT", "Obat berubah. Muat ulang sebelum mengoreksi.");
      await tx.recordRevision.create({ data: { userId, regimenId: id, version: old.version, reason, snapshot: JSON.parse(JSON.stringify(regimenView(old))) } });
      await recordAudit(tx, { userId, eventType: "medication_regimen_corrected", metadata: { recordId: id, version: old.version + 1 } });
      return (await repo.regimen(userId, id, tx))!;
    });
    return regimenView(row);
  },
  async revisions(userId: string, id: string) {
    await this.get(userId, id);
    return { items: await prisma.recordRevision.findMany({ where: { userId, regimenId: id }, orderBy: { version: "desc" } }) };
  },

  async createSchedule(userId: string, regimenId: string, input: ScheduleInput) {
    await requireHealth(userId);
    await needRegimen(userId, regimenId);
    const hash = sha({ ...input, regimenId });
    try {
      const saved = await prisma.$transaction(async (tx) => {
        const old = await tx.medicationSchedule.findFirst({ where: { id: input.id, userId } });
        if (old) {
          if (old.createHash !== hash) throw conflict("IDEMPOTENCY_CONFLICT", "ID jadwal sudah digunakan dengan isi berbeda.");
          return old;
        }
        return tx.medicationSchedule.create({ data: { ...input, effectiveFrom: new Date(input.effectiveFrom + "T00:00:00Z"), regimenId, userId, createHash: hash } });
      });
      return scheduleView(saved);
    } catch (e) {
      if (isUnique(e)) throw conflict("IDEMPOTENCY_CONFLICT", "ID jadwal sudah digunakan.");
      throw e;
    }
  },
  async listSchedules(userId: string, regimenId: string) {
    await requireHealth(userId);
    await needRegimen(userId, regimenId);
    const rows = await prisma.medicationSchedule.findMany({ where: { userId, regimenId }, orderBy: [{ enabled: "desc" }, { localTime: "asc" }] });
    return { items: rows.map(scheduleView) };
  },
  /** Changing a schedule never rewrites past intakes: each intake keeps its own snapshot. */
  async updateSchedule(userId: string, regimenId: string, id: string, input: SchedulePatch) {
    await requireHealth(userId);
    const old = await repo.schedule(userId, regimenId, id);
    if (!old) throw notFound("SCHEDULE_NOT_FOUND", "Jadwal tidak ditemukan.");
    const { enabled, effectiveFrom, ...rest } = input;
    const saved = await prisma.medicationSchedule.update({ where: { id }, data: { ...rest, ...(effectiveFrom ? { effectiveFrom: new Date(effectiveFrom + "T00:00:00Z") } : {}), ...(enabled === undefined ? {} : { enabled, disabledAt: enabled ? null : new Date() }) } });
    return scheduleView(saved);
  },

  async createIntake(userId: string, regimenId: string, input: IntakeInput) {
    await requireHealth(userId);
    const settings = await preferencesService.get(userId);
    const hash = sha({ ...input, regimenId });
    try {
      const row = await prisma.$transaction(async (tx) => {
        const old = await tx.medicationIntake.findFirst({ where: { id: input.id, userId } });
        if (old) {
          if (old.createHash !== hash) throw conflict("IDEMPOTENCY_CONFLICT", "ID konsumsi sudah digunakan dengan isi berbeda.");
          return old;
        }
        const regimen = await needRegimen(userId, regimenId, tx);
        const schedule = input.scheduleId ? await repo.schedule(userId, regimenId, input.scheduleId, tx) : null;
        if (input.scheduleId && !schedule) throw notFound("SCHEDULE_NOT_FOUND", "Jadwal tidak ditemukan.");
        const takenAt = input.status === "taken" ? new Date(input.takenAt ?? Date.now()) : null;
        if (input.status !== "taken" && input.takenAt) throw unprocessable("TAKEN_AT_NOT_ALLOWED", "Waktu minum hanya untuk status sudah diminum.");
        const scheduledAt = input.scheduledAt ? new Date(input.scheduledAt) : null;
        const saved = await tx.medicationIntake.create({ data: { id: input.id, userId, regimenId, scheduleId: input.scheduleId, scheduledAt, takenAt, eventAt: takenAt ?? scheduledAt ?? new Date(), status: input.status, notes: input.notes, medicationSnapshot: snapshotOf(regimen, schedule?.localTime), createHash: hash } });
        await recordAudit(tx, { userId, eventType: "medication_intake_recorded", metadata: { recordId: saved.id } });
        await emitRecordEvent(tx, { userId, kind: "medication_intake", action: "created", recordId: saved.id, revision: saved.version, occurredAt: saved.eventAt, localDates: [localRecordTime(saved.eventAt, settings.timezone).localDate], timezone: settings.timezone, source: "manual", quality: saved.status });
        return saved;
      });
      return intakeView(row, settings.timezone);
    } catch (e) {
      if (isUnique(e)) {
        const old = await prisma.medicationIntake.findFirst({ where: { id: input.id, userId } });
        if (old?.createHash === hash) return intakeView(old, settings.timezone);
        throw conflict("INTAKE_ALREADY_RECORDED", "Konsumsi untuk jadwal ini sudah tercatat. Koreksi catatan yang ada.");
      }
      throw e;
    }
  },
  async listIntakes(userId: string, regimenId: string, q: { cursor?: string; limit: number; archived: string }) {
    await requireHealth(userId);
    await needRegimen(userId, regimenId);
    const settings = await preferencesService.get(userId);
    const anchor = q.cursor ? await repo.intake(userId, regimenId, q.cursor) : null;
    if (q.cursor && !anchor) throw notFound("CURSOR_NOT_FOUND", "Cursor tidak ditemukan.");
    const rows = await prisma.medicationIntake.findMany({
      where: { userId, regimenId, archivedAt: q.archived === "true" ? { not: null } : null, ...(anchor ? { OR: [{ eventAt: { lt: anchor.eventAt } }, { eventAt: anchor.eventAt, id: { lt: anchor.id } }] } : {}) },
      orderBy: [{ eventAt: "desc" }, { id: "desc" }],
      take: q.limit + 1,
    });
    const page = rows.slice(0, q.limit);
    return { items: page.map((r) => intakeView(r, settings.timezone)), nextCursor: rows.length > q.limit ? page.at(-1)!.id : null, timezone: settings.timezone };
  },
  async getIntake(userId: string, regimenId: string, id: string) {
    await requireHealth(userId);
    const [row, settings] = await Promise.all([repo.intake(userId, regimenId, id), preferencesService.get(userId)]);
    if (!row) throw notFound("INTAKE_NOT_FOUND", "Catatan konsumsi tidak ditemukan.");
    return intakeView(row, settings.timezone);
  },
  async updateIntake(userId: string, regimenId: string, id: string, input: IntakePatch) {
    await requireHealth(userId);
    const settings = await preferencesService.get(userId);
    const row = await prisma.$transaction(async (tx) => {
      const old = await repo.intake(userId, regimenId, id, tx);
      if (!old) throw notFound("INTAKE_NOT_FOUND", "Catatan konsumsi tidak ditemukan.");
      if (old.version !== input.expectedVersion) throw conflict("VERSION_CONFLICT", "Catatan berubah. Muat ulang sebelum mengoreksi.");
      const status = input.status ?? (old.status as "taken" | "skipped" | "unknown");
      const takenAt = status === "taken" ? new Date(input.takenAt ?? old.takenAt ?? Date.now()) : null;
      const changed = await tx.medicationIntake.updateMany({
        where: { id, userId, version: input.expectedVersion },
        data: { status, takenAt, eventAt: takenAt ?? old.scheduledAt ?? old.eventAt, ...(input.notes !== undefined ? { notes: input.notes } : {}), archivedAt: input.archived === undefined ? undefined : input.archived ? new Date() : null, version: { increment: 1 } },
      });
      if (changed.count !== 1) throw conflict("VERSION_CONFLICT", "Catatan berubah. Muat ulang sebelum mengoreksi.");
      await tx.recordRevision.create({ data: { userId, intakeId: id, version: old.version, reason: input.reason, snapshot: JSON.parse(JSON.stringify(intakeView(old, settings.timezone))) } });
      await recordAudit(tx, { userId, eventType: input.archived ? "medication_intake_archived" : "medication_intake_corrected", metadata: { recordId: id, version: old.version + 1 } });
      const after = (await repo.intake(userId, regimenId, id, tx))!;
      await emitRecordEvent(tx, { userId, kind: "medication_intake", action: input.archived ? "archived" : "corrected", recordId: id, revision: after.version, occurredAt: after.eventAt, localDates: [localRecordTime(old.eventAt, settings.timezone).localDate, localRecordTime(after.eventAt, settings.timezone).localDate], timezone: settings.timezone, source: "manual", quality: after.status });
      return after;
    });
    return intakeView(row, settings.timezone);
  },

  /** Today's occurrences. Unconfirmed stays "unknown": never assumed taken or missed. */
  async today(userId: string, date?: string) {
    await requireHealth(userId);
    const settings = await preferencesService.get(userId);
    const local = date ?? localRecordTime(new Date(), settings.timezone).localDate;
    const regimens = await prisma.medicationRegimen.findMany({
      where: { userId, status: "active", OR: [{ startDate: null }, { startDate: { lte: new Date(local + "T00:00:00Z") } }], AND: [{ OR: [{ endDate: null }, { endDate: { gte: new Date(local + "T00:00:00Z") } }] }] },
      include: { schedules: true },
    });
    const byId = new Map(regimens.map((r) => [r.id, r]));
    const occ = occurrencesFor(local, regimens.flatMap((r) => r.schedules));
    const intakes = occ.length ? await prisma.medicationIntake.findMany({ where: { userId, archivedAt: null, scheduleId: { in: occ.map((o) => o.scheduleId) }, scheduledAt: { in: occ.map((o) => o.scheduledAt) } } }) : [];
    const items = occ.map((o) => {
      const intake = intakes.find((i) => i.scheduleId === o.scheduleId && i.scheduledAt?.getTime() === o.scheduledAt.getTime());
      const r = byId.get(o.regimenId)!;
      return { regimenId: o.regimenId, scheduleId: o.scheduleId, name: r.name, strength: r.strength, localTime: o.localTime, scheduledAt: o.scheduledAt.toISOString(), status: (intake?.status ?? "unknown") as "taken" | "skipped" | "unknown", intakeId: intake?.id ?? null, intakeVersion: intake?.version ?? null };
    });
    return { date: local, timezone: settings.timezone, items, ...summarizeOccurrences(items), computationVersion: "medication-occurrence-v1", computedAt: new Date().toISOString() };
  },
  async upcoming(userId: string, days: number, now = new Date()) {
    await requireHealth(userId);
    const settings = await preferencesService.get(userId);
    const today = localRecordTime(now, settings.timezone).localDate;
    const out: { regimenId: string; scheduleId: string; scheduledAt: string; title: string; body: string }[] = [];
    for (let i = 0; i < days; i++) {
      const date = new Date(Date.parse(today + "T00:00:00Z") + i * 86_400_000).toISOString().slice(0, 10);
      const t = await this.today(userId, date);
      for (const o of t.items) if (o.status === "unknown" && new Date(o.scheduledAt) > now) out.push({ regimenId: o.regimenId, scheduleId: o.scheduleId, scheduledAt: o.scheduledAt, title: "Waktunya obat", body: "Ketuk Sudah bila sudah diminum, atau buka beOkay." });
    }
    return { timezone: settings.timezone, items: out.slice(0, 40) };
  },
};
export { zonedToUtc };
