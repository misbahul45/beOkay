import { z } from "zod";
import { CONSENT_PURPOSES, CONSENT_SOURCES } from "./consent.policy.ts";

const purposes = z.array(z.enum(CONSENT_PURPOSES)).min(1).max(CONSENT_PURPOSES.length);

const unique = (items: string[]) => new Set(items).size === items.length;

export const grantConsentSchema = z.object({
  policyVersion: z.string().min(1).max(32),
  purposes: purposes.refine(unique, "duplicate purposes"),
  source: z.enum(CONSENT_SOURCES).default("api"),
});

export const withdrawConsentSchema = z.object({
  purposes: purposes.refine(unique, "duplicate purposes"),
});

export type GrantConsentInput = z.infer<typeof grantConsentSchema>;
export type WithdrawConsentInput = z.infer<typeof withdrawConsentSchema>;
