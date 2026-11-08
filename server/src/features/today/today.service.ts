import { consentService } from "../consent/consent.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { profileService } from "../profile/profile.service.ts";
import { buildToday } from "./today.model.ts";
import { nutritionService } from "../nutrition/nutrition.service.ts";
import { glucoseService } from "../glucose/glucose.service.ts";
import { activityService } from "../activity/activity.service.ts";
import { timelineService } from "../timeline/timeline.service.ts";

export const todayService = {
  async get(userId: string) {
    await consentService.requireConsent(userId, "health_data_processing");
    await consentService.requireConsent(userId, "descriptive_summaries");
    const [profile, preferences] = await Promise.all([
      profileService.get(userId),
      preferencesService.get(userId),
    ]);
    const today = buildToday(
      {
        displayName: profile.displayName,
        timezone: preferences.timezone,
        glucoseUnit: preferences.glucoseUnit,
      },
      new Date(),
    );
    const [nutrition, glucose, activity, timeline] = await Promise.all([
      nutritionService.daily(userId, today.date),
      glucoseService.daily(userId, today.date),
      activityService.daily(userId, today.date),
      timelineService.list(userId, {
        date: today.date,
        limit: 5,
        domain: "all",
        archived: "false",
      }),
    ]);
    return {
      ...today,
      computationVersion: "today-activity-v1",
      metrics: today.metrics.map((metric) =>
        metric.domain === "nutrition"
          ? { domain: "nutrition", availability: "AVAILABLE", value: nutrition }
          : metric.domain === "glucose"
            ? { domain: "glucose", availability: "AVAILABLE", value: glucose }
            : metric.domain === "activity"
              ? {
                  domain: "activity",
                  availability: "AVAILABLE",
                  value: activity,
                }
              : metric,
      ),
      nutrition,
      glucose,
      activity,
      timeline: {
        availability: "AVAILABLE",
        ...timeline,
      },
    };
  },
};
