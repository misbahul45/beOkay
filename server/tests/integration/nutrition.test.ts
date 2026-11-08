import { expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";

test("Nutrition lifecycle persists, snapshots, corrections, consent and ownership", async () => {
  const api = process.env.API_BASE_URL;
  if (!api || process.env.NODE_ENV !== "test")
    throw new Error("Isolated API required");
  const ids: string[] = [];
  const call = (
    path: string,
    token?: string,
    body?: object,
    method = body ? "POST" : "GET",
  ) =>
    fetch(api + path, {
      method,
      headers: {
        ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...(body ? { "content-type": "application/json" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
  async function actor(name: string) {
    const id = crypto.randomUUID(),
      token = crypto.randomUUID();
    ids.push(id);
    await prisma.users.create({
      data: {
        id,
        name,
        email: `nutrition-${id}@example.test`,
        emailVerified: true,
        createdAt: new Date(),
        updatedAt: new Date(),
      },
    });
    await prisma.sessions.create({
      data: {
        id: crypto.randomUUID(),
        userId: id,
        token,
        createdAt: new Date(),
        updatedAt: new Date(),
        expiresAt: new Date(Date.now() + 3600000),
      },
    });
    return { id, token };
  }
  try {
    const a = await actor("Nutrition A"),
      b = await actor("Nutrition B");
    expect((await call("/api/me/meals")).status).toBe(401);
    expect((await call("/api/me/meals", a.token)).status).toBe(403);
    const policy = (await (
      await call("/api/consent-policies/current")
    ).json()) as any;
    for (const user of [a, b])
      expect(
        (
          await call("/api/me/consents", user.token, {
            policyVersion: policy.version,
            purposes: ["health_data_processing", "descriptive_summaries"],
          })
        ).status,
      ).toBe(200);
    const per100g = {
      calories: 200,
      carbohydrates: 30,
      protein: 5,
      fat: null,
      fiber: null,
    };
    const foodInput = {
      name: "Synthetic reference",
      source: "synthetic integration fixture",
      status: "user_reported",
      per100g,
    };
    const foodResponse = await call("/api/me/foods", a.token, foodInput);
    expect(foodResponse.status).toBe(201);
    const food = (await foodResponse.json()) as any;
    expect(
      (
        (await (
          await call("/api/foods/search?q=Synthetic", b.token)
        ).json()) as any
      ).items,
    ).toHaveLength(0);
    const input = {
      id: crypto.randomUUID(),
      category: "lunch",
      consumedAt: new Date(Date.now() - 60000).toISOString(),
      items: [
        { name: food.name, foodId: food.id, quantity: 150, unit: "g" },
        { name: "Unknown item", quantity: 1, unit: "portion" },
      ],
    };
    expect(
      (await call("/api/me/meals", a.token, { ...input, items: [] })).status,
    ).toBe(400);
    expect(
      (
        await call("/api/me/meals", b.token, {
          ...input,
          id: crypto.randomUUID(),
        })
      ).status,
    ).toBe(404);
    const created = await call("/api/me/meals", a.token, input);
    expect(created.status).toBe(201);
    const meal = (await created.json()) as any;
    expect(meal.totals.calories.value).toBe(300);
    expect(meal.totals.calories.coverage).toBe("PARTIAL");
    expect(meal.totals.fat.value).toBeNull();
    expect((await call("/api/me/meals", a.token, input)).status).toBe(201);
    expect(
      ((await (await call("/api/me/meals", a.token)).json()) as any).items,
    ).toHaveLength(1);
    expect((await call(`/api/me/meals/${meal.id}`, b.token)).status).toBe(404);
    expect(
      (
        await call(
          `/api/me/meals/${meal.id}`,
          b.token,
          { expectedVersion: 1, reason: "unauthorized", notes: "changed" },
          "PATCH",
        )
      ).status,
    ).toBe(404);
    expect(
      (
        await call(
          `/api/me/foods/${food.id}`,
          a.token,
          { ...foodInput, per100g: { ...per100g, calories: 999 } },
          "PATCH",
        )
      ).status,
    ).toBe(200);
    expect(
      ((await (await call(`/api/me/meals/${meal.id}`, a.token)).json()) as any)
        .totals.calories.value,
    ).toBe(300);
    const patch = {
      expectedVersion: 1,
      reason: "Correct weighed quantity",
      items: meal.items.map((item: any) => ({
        id: item.id,
        name: item.name,
        quantity: item.foodId ? 200 : 1,
        unit: item.unit,
        grams: null,
        gramsBasis: null,
      })),
    };
    const concurrent = await Promise.all([
      call(`/api/me/meals/${meal.id}`, a.token, patch, "PATCH"),
      call(`/api/me/meals/${meal.id}`, a.token, patch, "PATCH"),
    ]);
    expect(concurrent.map((r) => r.status).sort()).toEqual([200, 409]);
    const corrected = (await (
      await call(`/api/me/meals/${meal.id}`, a.token)
    ).json()) as any;
    expect(corrected.version).toBe(2);
    expect(corrected.totals.calories.value).toBe(400);
    const revisions = (await (
      await call(`/api/me/meals/${meal.id}/revisions`, a.token)
    ).json()) as any;
    expect(revisions.items).toHaveLength(1);
    expect(revisions.items[0].snapshot.totals.calories.value).toBe(300);
    const today = (await (await call("/api/me/today", a.token)).json()) as any;
    expect(today.nutrition.mealCount).toBe(1);
    expect(today.nutrition.totals.calories.value).toBe(400);
    const daily = (await (
      await call(`/api/me/summaries/daily?date=${corrected.localDate}`, a.token)
    ).json()) as any;
    expect(daily.mealCount).toBe(1);
    expect(daily.freshness).toBe("CURRENT");
    const timeline = (await (
      await call("/api/me/timeline", a.token)
    ).json()) as any;
    expect(timeline.items[0].recordId).toBe(meal.id);
    const extra = (await (
      await call("/api/me/meals", a.token, {
        ...input,
        id: crypto.randomUUID(),
        items: [{ name: "Other unknown", quantity: 1, unit: "piece" }],
      })
    ).json()) as any;
    const renamed = await call(
      `/api/me/meals/${extra.id}`,
      a.token,
      {
        expectedVersion: 1,
        reason: "Correct free-text item name",
        items: [
          {
            id: extra.items[0].id,
            name: "Renamed unknown item",
            quantity: 1,
            unit: "piece",
          },
        ],
      },
      "PATCH",
    );
    expect(renamed.status).toBe(200);
    expect(((await renamed.json()) as any).items[0].name).toBe(
      "Renamed unknown item",
    );
    const page = (await (
      await call("/api/me/meals?limit=1", a.token)
    ).json()) as any;
    expect(page.items).toHaveLength(1);
    expect(page.nextCursor).toBeTruthy();
    const next = (await (
      await call(`/api/me/meals?limit=1&cursor=${page.nextCursor}`, a.token)
    ).json()) as any;
    expect(next.items[0].id).not.toBe(page.items[0].id);
    expect(
      (
        await call(
          `/api/me/meals/${meal.id}`,
          a.token,
          {
            expectedVersion: 2,
            reason: "Archive incorrect entry",
            archived: true,
          },
          "PATCH",
        )
      ).status,
    ).toBe(200);
    const after = (await (await call("/api/me/today", a.token)).json()) as any;
    expect(after.nutrition.mealCount).toBe(1);
    expect(after.nutrition.totals.calories.value).toBeNull();
    expect(
      (
        (await (
          await call("/api/me/meals?archived=true", a.token)
        ).json()) as any
      ).items[0].id,
    ).toBe(meal.id);
    const archivedDate = await call(
      `/api/me/meals?archived=true&date=${corrected.localDate}`,
      a.token,
    );
    expect(((await archivedDate.json()) as any).items[0]?.id).toBe(meal.id);
    await call(
      "/api/me/preferences",
      a.token,
      { timezone: "America/New_York" },
      "PATCH",
    );
    for (const consumedAt of [
      "2026-03-08T04:59:00Z",
      "2026-03-08T05:00:00Z",
      "2026-03-09T03:59:00Z",
      "2026-03-09T04:00:00Z",
    ]) {
      expect(
        (
          await call("/api/me/meals", a.token, {
            ...input,
            id: crypto.randomUUID(),
            consumedAt,
            items: [{ name: "DST fixture", quantity: 1, unit: "piece" }],
          })
        ).status,
      ).toBe(201);
    }
    const dst = (await (
      await call("/api/me/summaries/daily?date=2026-03-08", a.token)
    ).json()) as any;
    expect(dst.mealCount).toBe(2);
    await expect(
      Promise.resolve(
        prisma.$executeRaw`UPDATE meal_items SET grams = NULL, grams_basis = NULL WHERE meal_id = ${meal.id}::uuid AND unit = 'g'`,
      ),
    ).rejects.toThrow();
    await call("/api/me/consents/withdraw", a.token, {
      purposes: ["health_data_processing"],
    });
    expect((await call(`/api/me/meals/${extra.id}`, a.token)).status).toBe(403);
    expect((await call("/api/foods/search?q=Synthetic", a.token)).status).toBe(
      403,
    );
  } finally {
    await prisma.users.deleteMany({ where: { id: { in: ids } } });
  }
}, 30000);
