import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { forbidden, unprocessable } from "../../shared/errors/app-error.ts";
import { emitDomainEvent } from "../../infrastructure/queue/events.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { currentPolicy, requiredPurposes, type ConsentPurpose } from "./consent.policy.ts";
import { consentRepository, type ConsentRow } from "./consent.repository.ts";
import type { GrantConsentInput, WithdrawConsentInput } from "./consent.schema.ts";

export type ConsentStatus = "granted" | "withdrawn" | "not_given" | "reconsent_required";

export type PurposeConsentView = {
  purpose: ConsentPurpose;
  required: boolean;
  status: ConsentStatus;
  policyVersion: string | null;
  grantedAt: string | null;
  withdrawnAt: string | null;
};

const iso = (value: Date | null) => (value ? value.toISOString() : null);

function toHistoryItem(row: ConsentRow) {
  return {
    id: row.id,
    purpose: row.purpose,
    policyVersion: row.policyVersion,
    status: row.withdrawnAt ? "withdrawn" : "granted",
    grantedAt: row.grantedAt.toISOString(),
    withdrawnAt: iso(row.withdrawnAt),
    source: row.source,
  };
}

export function summarize(rows: ConsentRow[]): PurposeConsentView[] {
  return currentPolicy.purposes.map((definition) => {
    const records = rows.filter((row) => row.purpose === definition.purpose);
    const active = records.find((row) => row.withdrawnAt === null);
    const latest = records[0];
    let status: ConsentStatus = "not_given";
    if (active) status = active.policyVersion === currentPolicy.version ? "granted" : "reconsent_required";
    else if (latest) status = "withdrawn";
    const shown = active ?? latest;
    return {
      purpose: definition.purpose,
      required: definition.required,
      status,
      policyVersion: shown?.policyVersion ?? null,
      grantedAt: iso(shown?.grantedAt ?? null),
      withdrawnAt: iso(shown?.withdrawnAt ?? null),
    };
  });
}

type Tx = Parameters<Parameters<typeof prisma.$transaction>[0]>[0];
const CASCADE_REASON = "CONSENT_WITHDRAWN";

export async function withdrawalCascade(tx: Tx, userId: string, purpose: string, now: Date) {
  if (purpose === "personalized_ai") {
    await tx.memoryItem.updateMany({ where: { userId, status: "PROPOSED" }, data: { status: "DISMISSED", version: { increment: 1 } } });
    await tx.memoryItem.updateMany({ where: { userId, status: "ACTIVE", pausedAt: null }, data: { pausedAt: now, pauseReason: CASCADE_REASON, version: { increment: 1 } } });
    await tx.coachingAction.updateMany({ where: { userId, status: "PROPOSED" }, data: { status: "EXPIRED", closeReason: CASCADE_REASON, decidedAt: now, version: { increment: 1 } } });
    await tx.recommendation.updateMany({ where: { userId, status: "OFFERED" }, data: { status: "INVALIDATED", version: { increment: 1 } } });
  }
  if (purpose === "social_outcomes_memory") {
    await tx.memoryItem.updateMany({ where: { userId, sourceType: "CHALLENGE", pausedAt: null }, data: { pausedAt: now, pauseReason: CASCADE_REASON } });
  }
}

export const consentService = {
  currentPolicy: () => currentPolicy,

  async overview(userId: string) {
    const rows = await consentRepository.listAll(userId);
    return {
      policyVersion: currentPolicy.version,
      purposes: summarize(rows),
      history: rows.map(toHistoryItem),
    };
  },

  async grant(userId: string, input: GrantConsentInput) {
    if (input.policyVersion !== currentPolicy.version) {
      throw unprocessable("POLICY_VERSION_MISMATCH", "Versi kebijakan sudah berubah. Muat ulang kebijakan terbaru.", {
        currentVersion: currentPolicy.version,
      });
    }
    try {
      await prisma.$transaction(async (tx) => {
        const now = new Date();
        for (const purpose of input.purposes) {
          const active = await consentRepository.findActive(userId, purpose, tx);
          if (active?.policyVersion === currentPolicy.version) continue;
          if (active) {
            await consentRepository.withdraw(tx, active.id, now);
            await recordAudit(tx, { userId, eventType: "consent_superseded", metadata: { purpose, fromVersion: active.policyVersion } });
          }
          await consentRepository.create(tx, { userId, purpose, policyVersion: currentPolicy.version, source: input.source, grantedAt: now });
          await recordAudit(tx, { userId, eventType: "consent_granted", metadata: { purpose, policyVersion: currentPolicy.version, source: input.source } });
          await emitDomainEvent(tx, { userId, type: "consent.granted", dedupeKey: `consent-granted:${userId}:${purpose}:${currentPolicy.version}:${now.getTime()}`, payload: { purpose, policyVersion: currentPolicy.version }, consentScope: purpose, occurredAt: now });
        }
      });
    } catch (error) {
      if (!(error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002")) throw error;
    }
    return this.overview(userId);
  },

  async withdraw(userId: string, input: WithdrawConsentInput) {
    await prisma.$transaction(async (tx) => {
      const now = new Date();
      for (const purpose of input.purposes) {
        const active = await consentRepository.findActive(userId, purpose, tx);
        if (!active) continue;
        await consentRepository.withdraw(tx, active.id, now);
        await recordAudit(tx, { userId, eventType: "consent_withdrawn", metadata: { purpose, policyVersion: active.policyVersion } });
        await emitDomainEvent(tx, { userId, type: "consent.withdrawn", dedupeKey: `consent-withdrawn:${active.id}`, payload: { purpose, policyVersion: active.policyVersion }, consentScope: purpose, occurredAt: now });
        await withdrawalCascade(tx, userId, purpose, now);
        if (purpose === "product_analytics") await tx.usageEvent.deleteMany({ where: { userId } });
      }
    });
    return this.overview(userId);
  },

  async hasRequiredConsents(userId: string, db?: Parameters<typeof consentRepository.listActive>[1]): Promise<boolean> {
    const rows = await consentRepository.listActive(userId, db);
    return requiredPurposes.every((purpose) =>
      rows.some((row) => row.purpose === purpose && row.policyVersion === currentPolicy.version),
    );
  },

  async hasConsent(userId: string, purpose: ConsentPurpose): Promise<boolean> {
    const rows = await consentRepository.listActive(userId);
    return rows.some((row) => row.purpose === purpose && row.policyVersion === currentPolicy.version);
  },

  async activePurposes(userId: string): Promise<Set<string>> {
    const rows = await consentRepository.listActive(userId);
    return new Set(rows.filter((row) => row.policyVersion === currentPolicy.version).map((row) => row.purpose));
  },

  async requireConsent(userId: string, purpose: ConsentPurpose) {
    const rows = await consentRepository.listActive(userId);
    const ok = rows.some((row) => row.purpose === purpose && row.policyVersion === currentPolicy.version);
    if (!ok) throw forbidden("CONSENT_REQUIRED", "Persetujuan yang diperlukan belum diberikan atau sudah ditarik.", { purpose });
  },
};
