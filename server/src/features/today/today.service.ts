import { consentService } from "../consent/consent.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { profileService } from "../profile/profile.service.ts";
import { buildToday } from "./today.model.ts";
import { nutritionService } from "../nutrition/nutrition.service.ts";

export const todayService = {
  async get(userId: string) {
    await consentService.requireConsent(userId, "health_data_processing");
    await consentService.requireConsent(userId, "descriptive_summaries");
    const [profile, preferences] = await Promise.all([profileService.get(userId), preferencesService.get(userId)]);
    const today=buildToday({ displayName: profile.displayName, timezone: preferences.timezone, glucoseUnit: preferences.glucoseUnit }, new Date());
    const nutrition=await nutritionService.daily(userId,today.date);
    return {...today,computationVersion:"today-nutrition-v1",metrics:today.metrics.map(metric=>metric.domain==="nutrition"?{domain:"nutrition",availability:"AVAILABLE",value:nutrition}:metric),nutrition,timeline:{availability:"AVAILABLE",supportedDomains:["meal"],items:nutrition.recent.map(meal=>({...meal,domain:"meal"}))}};
  },
};
