import { z } from "zod";
import { GLUCOSE_UNITS } from "./glucose-units.ts";

export const SUPPORTED_LOCALES = ["id-ID"] as const;
export const TEXT_SIZES = ["system", "large", "extra_large"] as const;

const IANA_SHAPE = /^[A-Za-z]+(?:[_+-]?[A-Za-z0-9]+)*(?:\/[A-Za-z0-9_+-]+){0,2}$/;

export function isValidTimeZone(value: string): boolean {
  if (value.length > 64 || !IANA_SHAPE.test(value)) return false;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value });
    return true;
  } catch {
    return false;
  }
}

export const updatePreferencesSchema = z
  .object({
    locale: z.enum(SUPPORTED_LOCALES).optional(),
    timezone: z.string().refine(isValidTimeZone, "invalid IANA time zone").optional(),
    glucoseUnit: z.enum(GLUCOSE_UNITS).optional(),
    textSize: z.enum(TEXT_SIZES).optional(),
    reduceMotion: z.boolean().optional(),
  })
  .refine((value) => Object.values(value).some((entry) => entry !== undefined), "at least one field");

export type UpdatePreferencesInput = z.infer<typeof updatePreferencesSchema>;
