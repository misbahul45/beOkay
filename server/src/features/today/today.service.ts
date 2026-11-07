import { consentService } from "../consent/consent.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { profileService } from "../profile/profile.service.ts";
import { buildToday } from "./today.model.ts";

export const todayService = {
  async get(userId: string) {
    await consentService.requireConsent(userId, "health_data_processing");
    await consentService.requireConsent(userId, "descriptive_summaries");
    const [profile, preferences] = await Promise.all([profileService.get(userId), preferencesService.get(userId)]);
    return buildToday({ displayName: profile.displayName, timezone: preferences.timezone, glucoseUnit: preferences.glucoseUnit }, new Date());
  },
};
