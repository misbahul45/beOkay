import { prisma } from "../../infrastructure/database/prisma.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { preferencesRepository, type SettingsRow } from "./preferences.repository.ts";
import type { UpdatePreferencesInput } from "./preferences.schema.ts";

export const DEFAULT_PREFERENCES = {
  locale: "id-ID",
  timezone: "Asia/Jakarta",
  glucoseUnit: "mg/dL",
  textSize: "system",
  reduceMotion: false,
} as const;

export type PreferencesView = {
  locale: string;
  timezone: string;
  glucoseUnit: string;
  textSize: string;
  reduceMotion: boolean;
  isDefault: boolean;
  updatedAt: string | null;
};

function toView(row: SettingsRow | null): PreferencesView {
  if (!row) return { ...DEFAULT_PREFERENCES, isDefault: true, updatedAt: null };
  return {
    locale: row.locale,
    timezone: row.timezone,
    glucoseUnit: row.glucoseUnit,
    textSize: row.textSize,
    reduceMotion: row.reduceMotion,
    isDefault: false,
    updatedAt: row.updatedAt.toISOString(),
  };
}

export const preferencesService = {
  async get(userId: string): Promise<PreferencesView> {
    return toView(await preferencesRepository.find(userId));
  },

  async update(userId: string, input: UpdatePreferencesInput): Promise<PreferencesView> {
    const data = Object.fromEntries(Object.entries(input).filter(([, value]) => value !== undefined));
    const row = await prisma.$transaction(async (tx) => {
      const saved = await preferencesRepository.upsert(tx, userId, data);
      await recordAudit(tx, { userId, eventType: "preferences_updated", metadata: { fields: Object.keys(data) } });
      return saved;
    });
    return toView(row);
  },
};
