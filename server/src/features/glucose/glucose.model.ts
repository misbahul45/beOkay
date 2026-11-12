import { Prisma } from "../../generated/prisma/client.ts";
import {
  MG_DL_PER_MMOL_L,
  type GlucoseUnit,
} from "../preferences/glucose-units.ts";
export const GLUCOSE_COUNTED_QUALITY = ["user_reported", "device_reported"] as const;
export function canonicalGlucose(value: number, unit: GlucoseUnit) {
  return unit === "mg/dL"
    ? new Prisma.Decimal(value)
    : new Prisma.Decimal(value).mul(MG_DL_PER_MMOL_L);
}
export function displayGlucose(value: Prisma.Decimal, unit: GlucoseUnit) {
  return (unit === "mg/dL" ? value : value.div(MG_DL_PER_MMOL_L))
    .toDecimalPlaces(unit === "mg/dL" ? 0 : 1)
    .toNumber();
}
