import { createHash } from "node:crypto";
import { ZodError } from "zod";
import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { AppError, badRequest } from "../../shared/errors/app-error.ts";
import { consentService } from "../consent/consent.service.ts";
import { activityService } from "../activity/activity.service.ts";
import { activityCreateSchema, activityPatchSchema } from "../activity/activity.schema.ts";
import { glucoseService } from "../glucose/glucose.service.ts";
import { glucoseCreateSchema, glucosePatchSchema } from "../glucose/glucose.schema.ts";
import { nutritionService } from "../nutrition/nutrition.service.ts";
import { mealCreateSchema, mealPatchSchema } from "../nutrition/nutrition.schema.ts";
import { medicationService } from "../medication/medication.service.ts";
import { intakeCreateSchema, intakePatchSchema } from "../medication/medication.schema.ts";
import { goalsService } from "../goals/goals.service.ts";
import { checkinCreateSchema, checkinPatchSchema } from "../goals/goals.schema.ts";
import { clinicalService } from "../clinical/clinical.service.ts";
import { labCreateSchema, labPatchSchema, vitalCreateSchema, vitalPatchSchema } from "../clinical/clinical.schema.ts";
import type { SyncOperationInput } from "./sync.schema.ts";

export type SyncStatus = "SYNCED" | "CONFLICT" | "NEEDS_REVIEW" | "SYNC_FAILED";
export type SyncItem = {
  operationId: string;
  status: SyncStatus;
  recordId: string;
  result?: unknown;
  error?: { code: string; message: string };
};

const hashOf = (op: SyncOperationInput) =>
  createHash("sha256")
    .update(
      JSON.stringify({
        domain: op.domain,
        recordId: op.recordId,
        operationType: op.operationType,
        parentId: op.parentId ?? null,
        payload: op.payload,
      }),
    )
    .digest("hex");

/** Memanggil service domain yang sama dengan jalur online; tidak ada logika bisnis ganda. */
async function apply(userId: string, op: SyncOperationInput): Promise<unknown> {
  const create = op.operationType === "create";
  const body = create ? { ...op.payload, id: op.recordId } : op.payload;
  const needParent = () => {
    if (!op.parentId) throw badRequest("PARENT_ID_REQUIRED", "parentId wajib untuk domain ini.");
    return op.parentId;
  };
  switch (op.domain) {
    case "meal":
      return create
        ? nutritionService.create(userId, mealCreateSchema.parse(body))
        : nutritionService.update(userId, op.recordId, mealPatchSchema.parse(body));
    case "glucose":
      return create
        ? glucoseService.create(userId, glucoseCreateSchema.parse(body))
        : glucoseService.update(userId, op.recordId, glucosePatchSchema.parse(body));
    case "activity":
      return create
        ? activityService.create(userId, activityCreateSchema.parse(body))
        : activityService.update(userId, op.recordId, activityPatchSchema.parse(body));
    case "medication_intake":
      return create
        ? medicationService.createIntake(userId, needParent(), intakeCreateSchema.parse(body))
        : medicationService.updateIntake(userId, needParent(), op.recordId, intakePatchSchema.parse(body));
    case "goal_checkin":
      return create
        ? goalsService.createCheckin(userId, needParent(), checkinCreateSchema.parse(body))
        : goalsService.updateCheckin(userId, needParent(), op.recordId, checkinPatchSchema.parse(body));
    case "vital":
      return create
        ? clinicalService.createVital(userId, vitalCreateSchema.parse(body))
        : clinicalService.updateVital(userId, op.recordId, vitalPatchSchema.parse(body));
    case "lab":
      return create
        ? clinicalService.createLab(userId, labCreateSchema.parse(body))
        : clinicalService.updateLab(userId, op.recordId, labPatchSchema.parse(body));
  }
}

function classify(error: unknown): { status: SyncStatus; code: string; message: string } {
  if (error instanceof ZodError)
    return { status: "NEEDS_REVIEW", code: "VALIDATION_ERROR", message: "Data tidak valid dan perlu diperiksa." };
  if (error instanceof AppError) {
    if (error.status === 409)
      return { status: "CONFLICT", code: error.code, message: error.message };
    if (error.status === 403 && error.code === "CONSENT_REQUIRED")
      return { status: "NEEDS_REVIEW", code: error.code, message: error.message };
    if (error.status >= 400 && error.status < 500)
      return { status: "NEEDS_REVIEW", code: error.code, message: error.message };
  }
  return { status: "SYNC_FAILED", code: "INTERNAL_ERROR", message: "Gagal diproses di server. Coba lagi nanti." };
}

function fromReceipt(row: {
  operationId: string;
  recordId: string;
  status: string;
  result: Prisma.JsonValue | null;
  errorCode: string | null;
}): SyncItem {
  return {
    operationId: row.operationId,
    recordId: row.recordId,
    status: row.status as SyncStatus,
    ...(row.result !== null ? { result: row.result } : {}),
    ...(row.errorCode
      ? { error: { code: row.errorCode, message: "Operasi ini sudah diproses sebelumnya." } }
      : {}),
  };
}

export const syncService = {
  async apply(userId: string, operations: SyncOperationInput[]): Promise<{ items: SyncItem[] }> {
    // Penarikan consent menghentikan sinkronisasi seluruhnya (403 dari requireConsent).
    await consentService.requireConsent(userId, "health_data_processing");
    const items: SyncItem[] = [];
    for (const op of operations) {
      const hash = hashOf(op);
      const prior = await prisma.syncOperation.findUnique({
        where: { userId_operationId: { userId, operationId: op.operationId } },
      });
      if (prior) {
        items.push(
          prior.payloadHash === hash
            ? fromReceipt(prior)
            : {
                operationId: op.operationId,
                recordId: op.recordId,
                status: "CONFLICT",
                error: { code: "OPERATION_ID_REUSED", message: "operationId dipakai ulang dengan isi berbeda." },
              },
        );
        continue;
      }
      let item: SyncItem;
      try {
        const result = await apply(userId, op);
        item = { operationId: op.operationId, recordId: op.recordId, status: "SYNCED", result };
      } catch (error) {
        const c = classify(error);
        item = {
          operationId: op.operationId,
          recordId: op.recordId,
          status: c.status,
          error: { code: c.code, message: c.message },
        };
      }
      // SYNC_FAILED (kesalahan sementara) tidak disimpan agar klien bisa mencoba lagi dengan operationId yang sama.
      if (item.status !== "SYNC_FAILED") {
        try {
          await prisma.syncOperation.create({
            data: {
              userId,
              operationId: op.operationId,
              payloadHash: hash,
              domain: op.domain,
              recordId: op.recordId,
              operationType: op.operationType,
              status: item.status,
              result: item.result === undefined ? undefined : (JSON.parse(JSON.stringify(item.result)) as Prisma.InputJsonValue),
              errorCode: item.error?.code,
            },
          });
        } catch (error) {
          if (!(error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002")) throw error;
        }
      }
      items.push(item);
    }
    return { items };
  },

  /** Ringkasan receipt milik sendiri; tanpa payload kesehatan. */
  async status(userId: string) {
    const rows = await prisma.syncOperation.findMany({
      where: { userId },
      orderBy: [{ completedAt: "desc" }, { id: "desc" }],
      take: 50,
      select: { operationId: true, domain: true, recordId: true, operationType: true, status: true, errorCode: true, completedAt: true },
    });
    return {
      items: rows.map((r) => ({ ...r, completedAt: r.completedAt.toISOString() })),
      counts: rows.reduce<Record<string, number>>((acc, r) => ({ ...acc, [r.status]: (acc[r.status] ?? 0) + 1 }), {}),
    };
  },
};
