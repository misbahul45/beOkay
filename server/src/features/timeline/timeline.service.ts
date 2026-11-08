import { z } from "zod";
import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { badRequest, notFound } from "../../shared/errors/app-error.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { consentService } from "../consent/consent.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import { displayGlucose } from "../glucose/glucose.model.ts";
import type { GlucoseUnit } from "../preferences/glucose-units.ts";
type Query = {
  date?: string;
  cursor?: string;
  limit: number;
  archived: string;
  domain: string;
};
const cursorShape = z
  .object({
    at: z.iso.datetime(),
    domain: z.enum(["meal", "glucose", "activity"]),
    id: z.uuid(),
  })
  .strict();
export const timelineService = {
  async list(userId: string, q: Query) {
    await consentService.requireConsent(userId, "health_data_processing");
    const settings = await preferencesService.get(userId);
    let cursor: z.infer<typeof cursorShape> | null = null;
    if (q.cursor) {
      if (z.uuid().safeParse(q.cursor).success) {
        const old = await prisma.mealLog.findFirst({
          where: { id: q.cursor, userId },
        });
        if (!old) throw notFound("CURSOR_NOT_FOUND", "Cursor tidak ditemukan.");
        cursor = {
          at: old.consumedAt.toISOString(),
          id: old.id,
          domain: "meal",
        };
      } else {
        try {
          cursor = cursorShape.parse(
            JSON.parse(Buffer.from(q.cursor, "base64url").toString("utf8")),
          );
        } catch {
          throw badRequest("INVALID_CURSOR", "Cursor tidak valid.");
        }
      }
    }
    type Event = {
      id: string;
      domain: "meal" | "glucose" | "activity";
      event_at: Date;
      category: string | null;
      item_count: bigint;
      value_mg_dl: Prisma.Decimal | null;
      original_value: Prisma.Decimal | null;
      original_unit: string | null;
      quality_status: string | null;
      meal_context: string | null;
      activity_type: string | null;
      duration_minutes: number | null;
    };
    const archived = q.archived === "true";
    const rows = await prisma.$queryRaw<Event[]>`WITH events AS (
    SELECT m.id,'meal'::text AS domain,m.consumed_at AS event_at,m.category,(SELECT count(*) FROM meal_items i WHERE i.meal_id=m.id) AS item_count,NULL::numeric AS value_mg_dl,NULL::numeric AS original_value,NULL::text AS original_unit,NULL::text AS quality_status,NULL::text AS meal_context,NULL::text AS activity_type,NULL::integer AS duration_minutes
    FROM meal_logs m WHERE m.user_id=${userId}::uuid AND (m.archived_at IS NOT NULL)=${archived}
    UNION ALL
    SELECT g.id,'glucose'::text,g.measured_at,NULL::text,0::bigint,g.value_mg_dl,g.original_value,g.original_unit,g.quality_status,g.meal_context,NULL::text,NULL::integer FROM glucose_observations g WHERE g.user_id=${userId}::uuid AND (g.archived_at IS NOT NULL)=${archived}
    UNION ALL
    SELECT a.id,'activity'::text,a.started_at,NULL::text,0::bigint,NULL::numeric,NULL::numeric,NULL::text,a.quality_status,NULL::text,a.activity_type,a.duration_minutes FROM activity_sessions a WHERE a.user_id=${userId}::uuid AND (a.archived_at IS NOT NULL)=${archived}
  ) SELECT * FROM events WHERE (${q.domain}='all' OR domain=${q.domain})
    AND (${q.date ?? null}::date IS NULL OR (event_at>=(${q.date ?? null}::date::timestamp AT TIME ZONE ${settings.timezone}) AND event_at<((${q.date ?? null}::date+1)::timestamp AT TIME ZONE ${settings.timezone})))
    AND (${cursor?.at ?? null}::timestamptz IS NULL OR (event_at,domain,id)<(${cursor?.at ?? null}::timestamptz,${cursor?.domain ?? ""}::text,${cursor?.id ?? "00000000-0000-0000-0000-000000000000"}::uuid))
    ORDER BY event_at DESC,domain DESC,id DESC LIMIT ${q.limit + 1}`;
    const page = rows.slice(0, q.limit),
      last = page.at(-1);
    return {
      supportedDomains: ["meal", "glucose", "activity"],
      timezone: settings.timezone,
      nextCursor:
        rows.length > q.limit && last
          ? Buffer.from(
              JSON.stringify({
                at: last.event_at.toISOString(),
                domain: last.domain,
                id: last.id,
              }),
            ).toString("base64url")
          : null,
      items: page.map((row) => ({
        domain: row.domain,
        recordId: row.id,
        occurredAt: row.event_at.toISOString(),
        ...localRecordTime(row.event_at, settings.timezone),
        ...(row.domain === "meal"
          ? { category: row.category, itemCount: Number(row.item_count) }
          : row.domain === "activity"
            ? {
                activityType: row.activity_type,
                durationMinutes: row.duration_minutes,
                qualityStatus: row.quality_status,
                source: "manual",
              }
            : {
                displayValue:
                  row.original_unit === settings.glucoseUnit
                    ? row.original_value!.toNumber()
                    : displayGlucose(
                        row.value_mg_dl!,
                        settings.glucoseUnit as GlucoseUnit,
                      ),
                displayUnit: settings.glucoseUnit,
                qualityStatus: row.quality_status,
                mealContext: row.meal_context,
                source: "manual_glucometer",
                measurementType: "capillary_blood",
              }),
      })),
    };
  },
};
