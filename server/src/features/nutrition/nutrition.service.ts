import { createHash } from "node:crypto";
import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { conflict, notFound } from "../../shared/errors/app-error.ts";
import { recordAudit } from "../../shared/audit/audit.ts";
import { consentService } from "../consent/consent.service.ts";
import { preferencesService } from "../preferences/preferences.service.ts";
import {
  calculateNutrition,
  numericNutrients,
  totalNutrition,
} from "./nutrition.model.ts";
import {
  mealInclude,
  nutritionRepository,
  type NutritionDb,
} from "./nutrition.repository.ts";
import {
  mealQuerySchema,
  type MealInput,
  type MealPatch,
} from "./nutrition.schema.ts";
import type { z } from "zod";

type MealRow = NonNullable<
  Awaited<ReturnType<typeof nutritionRepository.meal>>
>;
function mealView(row: MealRow, timezone: string) {
  const items = row.items.map((item) => {
    const per100g = numericNutrients(item);
    const grams = item.grams?.toNumber() ?? null;
    return {
      ...item,
      quantity: item.quantity.toNumber(),
      grams,
      per100g,
      nutrition: calculateNutrition(per100g, grams),
    };
  });
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(row.consumedAt);
  const p = (key: string) => parts.find((x) => x.type === key)!.value;
  return {
    id: row.id,
    category: row.category,
    consumedAt: row.consumedAt.toISOString(),
    localDate: `${p("year")}-${p("month")}-${p("day")}`,
    localTime: `${p("hour")}:${p("minute")}`,
    timezone,
    notes: row.notes,
    version: row.version,
    archivedAt: row.archivedAt?.toISOString() ?? null,
    captureMethod: row.captureMethod,
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
    items,
    totals: totalNutrition(items.map((item) => item.nutrition)),
  };
}
async function snapshotItems(
  db: NutritionDb,
  userId: string,
  items: MealInput["items"],
  previous?: MealRow,
) {
  return Promise.all(
    items.map(async (input) => {
      const old = input.id
        ? previous?.items.find((item) => item.id === input.id)
        : undefined;
      if (input.id && !old)
        throw conflict(
          "INVALID_ITEM_REFERENCE",
          "Item tidak berasal dari catatan ini.",
        );
      const referenceId =
        input.foodId === undefined ? (old?.foodId ?? null) : input.foodId;
      const same = old && referenceId === old.foodId;
      const food =
        referenceId && !same
          ? await nutritionRepository.food(userId, referenceId, db)
          : null;
      if (referenceId && !same && !food)
        throw notFound("FOOD_NOT_FOUND", "Makanan tidak ditemukan.");
      const source = same ? old : food;
      return {
        id: old?.id ?? crypto.randomUUID(),
        foodId: referenceId,
        name: same && old.foodId ? old.name : (food?.name ?? input.name),
        quantity: input.quantity,
        unit: input.unit,
        grams: input.unit === "g" ? input.quantity : input.grams,
        gramsBasis:
          input.unit === "g"
            ? "weighed"
            : input.grams === null
              ? null
              : input.gramsBasis,
        source: source?.source ?? "user_reported",
        sourceVersion: source?.sourceVersion ?? null,
        status: source?.status ?? "unknown",
        calories: source?.calories ?? null,
        carbohydrates: source?.carbohydrates ?? null,
        protein: source?.protein ?? null,
        fat: source?.fat ?? null,
        fiber: source?.fiber ?? null,
      };
    }),
  );
}
async function health(userId: string) {
  await consentService.requireConsent(userId, "health_data_processing");
}
const pref = (userId: string) => preferencesService.get(userId);
export const nutritionService = {
  async searchFoods(userId: string, q: string) {
    await health(userId);
    const rows = await prisma.foodCatalog.findMany({
      where: {
        OR: [{ userId }, { userId: null }],
        name: { contains: q, mode: "insensitive" },
      },
      orderBy: [{ name: "asc" }, { id: "asc" }],
      take: 20,
    });
    return {
      items: rows.map((row) => ({ ...row, per100g: numericNutrients(row) })),
    };
  },
  async createFood(
    userId: string,
    input: {
      name: string;
      source: string;
      sourceVersion: string | null;
      status: string;
      per100g: Record<string, number | null>;
    },
  ) {
    await health(userId);
    const row = await prisma.$transaction(async (tx) => {
      const saved = await tx.foodCatalog.create({
        data: {
          userId,
          name: input.name,
          source: input.source,
          sourceVersion: input.sourceVersion,
          status: input.status,
          ...input.per100g,
        },
      });
      await recordAudit(tx, {
        userId,
        eventType: "food_created",
        metadata: { recordId: saved.id },
      });
      return saved;
    });
    return { ...row, per100g: numericNutrients(row) };
  },
  async updateFood(
    userId: string,
    id: string,
    input: {
      name: string;
      source: string;
      sourceVersion: string | null;
      status: string;
      per100g: Record<string, number | null>;
    },
  ) {
    await health(userId);
    return prisma.$transaction(async (tx) => {
      const found = await tx.foodCatalog.findFirst({ where: { id, userId } });
      if (!found) throw notFound("FOOD_NOT_FOUND", "Makanan tidak ditemukan.");
      const row = await tx.foodCatalog.update({
        where: { id },
        data: {
          name: input.name,
          source: input.source,
          sourceVersion: input.sourceVersion,
          status: input.status,
          ...input.per100g,
        },
      });
      await recordAudit(tx, {
        userId,
        eventType: "food_updated",
        metadata: { recordId: id },
      });
      return { ...row, per100g: numericNutrients(row) };
    });
  },
  async create(userId: string, input: MealInput) {
    await health(userId);
    const settings = await pref(userId);
    const hash = createHash("sha256")
      .update(JSON.stringify(input))
      .digest("hex");
    try {
      const row = await prisma.$transaction(async (tx) => {
        const previous = await nutritionRepository.meal(userId, input.id, tx);
        if (previous) {
          if (previous.createHash !== hash)
            throw conflict(
              "IDEMPOTENCY_CONFLICT",
              "ID catatan sudah digunakan dengan isi berbeda.",
            );
          return previous;
        }
        const items = await snapshotItems(tx, userId, input.items);
        const saved = await tx.mealLog.create({
          data: {
            id: input.id,
            userId,
            category: input.category,
            consumedAt: new Date(input.consumedAt),
            notes: input.notes,
            createHash: hash,
            items: { create: items },
          },
          include: mealInclude,
        });
        await recordAudit(tx, {
          userId,
          eventType: "meal_created",
          metadata: { recordId: saved.id },
        });
        return saved;
      });
      return mealView(row, settings.timezone);
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === "P2002"
      ) {
        const row = await nutritionRepository.meal(userId, input.id);
        if (row?.createHash === hash) return mealView(row, settings.timezone);
        throw conflict("IDEMPOTENCY_CONFLICT", "ID catatan sudah digunakan.");
      }
      throw error;
    }
  },
  async get(userId: string, id: string) {
    await health(userId);
    const [row, settings] = await Promise.all([
      nutritionRepository.meal(userId, id),
      pref(userId),
    ]);
    if (!row) throw notFound("MEAL_NOT_FOUND", "Catatan tidak ditemukan.");
    return mealView(row, settings.timezone);
  },
  async update(userId: string, id: string, input: MealPatch) {
    await health(userId);
    const settings = await pref(userId);
    const row = await prisma.$transaction(async (tx) => {
      const current = await nutritionRepository.meal(userId, id, tx);
      if (!current)
        throw notFound("MEAL_NOT_FOUND", "Catatan tidak ditemukan.");
      if (current.version !== input.expectedVersion)
        throw conflict(
          "VERSION_CONFLICT",
          "Catatan berubah. Muat ulang sebelum mengoreksi.",
        );
      const items = input.items
        ? await snapshotItems(tx, userId, input.items, current)
        : null;
      const changed = await tx.mealLog.updateMany({
        where: { id, userId, version: input.expectedVersion },
        data: {
          category: input.category,
          consumedAt: input.consumedAt ? new Date(input.consumedAt) : undefined,
          notes: input.notes,
          archivedAt:
            input.archived === undefined
              ? undefined
              : input.archived
                ? new Date()
                : null,
          version: { increment: 1 },
        },
      });
      if (changed.count !== 1)
        throw conflict(
          "VERSION_CONFLICT",
          "Catatan berubah. Muat ulang sebelum mengoreksi.",
        );
      await tx.recordRevision.create({
        data: {
          userId,
          mealId: id,
          version: current.version,
          reason: input.reason,
          snapshot: JSON.parse(
            JSON.stringify(mealView(current, settings.timezone)),
          ),
        },
      });
      if (items) {
        await tx.mealItem.deleteMany({ where: { mealId: id } });
        await tx.mealItem.createMany({
          data: items.map((item) => ({ ...item, mealId: id })),
        });
      }
      await recordAudit(tx, {
        userId,
        eventType: input.archived ? "meal_archived" : "meal_corrected",
        metadata: { recordId: id, version: current.version + 1 },
      });
      return (await nutritionRepository.meal(userId, id, tx))!;
    });
    return mealView(row, settings.timezone);
  },
  async revisions(userId: string, id: string) {
    await this.get(userId, id);
    return {
      items: await prisma.recordRevision.findMany({
        where: { userId, mealId: id },
        orderBy: { version: "desc" },
      }),
    };
  },
  async list(userId: string, query: z.infer<typeof mealQuerySchema>) {
    await health(userId);
    const settings = await pref(userId);
    return prisma.$transaction(
      async (db) => {
        const ids = query.date
          ? await nutritionRepository.dateIds(
              userId,
              query.date,
              settings.timezone,
              db,
              query.archived === "true",
            )
          : null;
        const anchor = query.cursor
          ? await nutritionRepository.meal(userId, query.cursor, db)
          : null;
        if (query.cursor && !anchor)
          throw notFound("CURSOR_NOT_FOUND", "Cursor tidak ditemukan.");
        const rows = await db.mealLog.findMany({
          where: {
            userId,
            archivedAt: query.archived === "true" ? { not: null } : null,
            ...(ids ? { id: { in: ids } } : {}),
            ...(anchor
              ? {
                  OR: [
                    { consumedAt: { lt: anchor.consumedAt } },
                    {
                      consumedAt: anchor.consumedAt,
                      id: { lt: anchor.id, ...(ids ? { in: ids } : {}) },
                    },
                  ],
                }
              : {}),
          },
          include: mealInclude,
          orderBy: [{ consumedAt: "desc" }, { id: "desc" }],
          take: query.limit + 1,
        });
        const more = rows.length > query.limit;
        const page = rows.slice(0, query.limit);
        return {
          items: page.map((row) => mealView(row, settings.timezone)),
          nextCursor: more ? page.at(-1)!.id : null,
          timezone: settings.timezone,
        };
      },
      { isolationLevel: "RepeatableRead" },
    );
  },
  /** Makan pada rentang waktu (dipakai tren). Tanpa memeriksa consent sendiri: pemanggil wajib sudah memeriksanya. */
  async mealsBetween(userId: string, from: Date, to: Date, timezone: string) {
    const rows = await prisma.mealLog.findMany({
      where: { userId, archivedAt: null, consumedAt: { gte: from, lt: to } },
      include: mealInclude,
      orderBy: [{ consumedAt: "asc" }, { id: "asc" }],
    });
    return rows.map((row) => mealView(row as MealRow, timezone));
  },
  async daily(userId: string, date?: string) {
    await health(userId);
    await consentService.requireConsent(userId, "descriptive_summaries");
    const settings = await pref(userId);
    const day =
      date ??
      new Intl.DateTimeFormat("en-CA", {
        timeZone: settings.timezone,
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
      }).format(new Date());
    const rows = await prisma.$transaction(
      async (db) => {
        const ids = await nutritionRepository.dateIds(
          userId,
          day,
          settings.timezone,
          db,
        );
        return db.mealLog.findMany({
          where: { userId, id: { in: ids } },
          include: mealInclude,
          orderBy: [{ consumedAt: "desc" }, { id: "desc" }],
        });
      },
      { isolationLevel: "RepeatableRead" },
    );
    const meals = rows.map((row) => mealView(row, settings.timezone));
    return {
      date: day,
      timezone: settings.timezone,
      mealCount: meals.length,
      totals: totalNutrition(
        meals.flatMap((meal) => meal.items.map((item) => item.nutrition)),
      ),
      recent: meals.slice(0, 5).map((meal) => ({
        id: meal.id,
        category: meal.category,
        consumedAt: meal.consumedAt,
        localTime: meal.localTime,
        itemCount: meal.items.length,
      })),
      analyticsState: meals.length ? "READY" : "INSUFFICIENT_DATA",
      freshness: "CURRENT",
      computationVersion: "nutrition-v1",
      computedAt: new Date().toISOString(),
    };
  },
};
