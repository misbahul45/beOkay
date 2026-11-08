import { expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";

test("Glucose lifecycle preserves source values and units, revisions and account boundaries", async () => {
  const api = process.env.API_BASE_URL;
  if (!api || process.env.NODE_ENV !== "test")
    throw new Error("Isolated test API required");
  const users: string[] = [];
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
  async function actor() {
    const id = crypto.randomUUID(),
      token = crypto.randomUUID();
    users.push(id);
    await prisma.users.create({
      data: {
        id,
        name: "Glucose fixture",
        email: `glucose-${id}@example.test`,
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
    const a = await actor(),
      b = await actor();
    expect((await call("/api/me/glucose")).status).toBe(401);
    expect((await call("/api/me/glucose", a.token)).status).toBe(403);
    const policy = (await (
      await call("/api/consent-policies/current")
    ).json()) as any;
    for (const actor of [a, b])
      await call("/api/me/consents", actor.token, {
        policyVersion: policy.version,
        purposes: ["health_data_processing", "descriptive_summaries"],
      });
    const measuredAt = new Date(Date.now() - 60000).toISOString();
    const input = {
      id: crypto.randomUUID(),
      originalValue: 5.5,
      originalUnit: "mmol/L",
      measuredAt,
      mealContext: "after_meal",
      notes: "Synthetic observation",
    };
    const created = await call("/api/me/glucose", a.token, input);
    expect(created.status).toBe(201);
    const record = (await created.json()) as any;
    expect(record.originalValue).toBe(5.5);
    expect(record.originalUnit).toBe("mmol/L");
    expect(record.valueMgDl).toBe(99.088);
    expect(record.displayValue).toBe(99);
    expect(record.source).toBe("manual_glucometer");
    expect(record.measurementType).toBe("capillary_blood");
    expect((await call("/api/me/glucose", a.token, input)).status).toBe(201);
    expect(
      (await call("/api/me/glucose", a.token, { ...input, originalValue: 6 }))
        .status,
    ).toBe(409);
    expect(
      ((await (await call("/api/me/glucose", a.token)).json()) as any).items,
    ).toHaveLength(1);
    expect((await call(`/api/me/glucose/${record.id}`, b.token)).status).toBe(
      404,
    );
    expect(
      (
        await call(
          `/api/me/glucose/${record.id}`,
          b.token,
          { expectedVersion: 1, reason: "forged owner", notes: "denied" },
          "PATCH",
        )
      ).status,
    ).toBe(404);
    expect(
      (await call(`/api/me/glucose/${record.id}/revisions`, b.token)).status,
    ).toBe(404);
    await call(
      "/api/me/preferences",
      a.token,
      { glucoseUnit: "mmol/L" },
      "PATCH",
    );
    const changed = (await (
      await call(`/api/me/glucose/${record.id}`, a.token)
    ).json()) as any;
    expect(changed.displayValue).toBe(5.5);
    expect(changed.valueMgDl).toBe(99.088);
    expect(changed.version).toBe(1);
    const correction = {
      expectedVersion: 1,
      reason: "Correct synthetic reading",
      originalValue: 6.1,
    };
    const concurrent = await Promise.all([
      call(`/api/me/glucose/${record.id}`, a.token, correction, "PATCH"),
      call(`/api/me/glucose/${record.id}`, a.token, correction, "PATCH"),
    ]);
    expect(concurrent.map((r) => r.status).sort()).toEqual([200, 409]);
    const corrected = (await (
      await call(`/api/me/glucose/${record.id}`, a.token)
    ).json()) as any;
    expect(corrected.version).toBe(2);
    expect(corrected.originalUnit).toBe("mmol/L");
    expect(corrected.mealContext).toBe("after_meal");
    expect(corrected.notes).toBe("Synthetic observation");
    expect(corrected.valueMgDl).toBe(109.8976);
    const revisions = (await (
      await call(`/api/me/glucose/${record.id}/revisions`, a.token)
    ).json()) as any;
    expect(revisions.items).toHaveLength(1);
    expect(revisions.items[0].snapshot.originalValue).toBe(5.5);
    const flagged = (await (
      await call("/api/me/glucose", a.token, {
        ...input,
        id: crypto.randomUUID(),
        originalValue: 20,
        qualityStatus: "needs_review",
      })
    ).json()) as any;
    expect(flagged.qualityFlags).toEqual(["user_flagged"]);
    const single = (await (
      await call("/api/me/glucose/summary", a.token)
    ).json()) as any;
    expect(single.count).toBe(2);
    expect(single.eligibleCount).toBe(1);
    expect(single.mean).toBeNull();
    const another = (await (
      await call("/api/me/glucose", a.token, {
        ...input,
        id: crypto.randomUUID(),
        originalValue: 5.9,
      })
    ).json()) as any;
    const summary = (await (
      await call("/api/me/glucose/summary", a.token)
    ).json()) as any;
    expect(summary.count).toBe(3);
    expect(summary.reviewCount).toBe(1);
    expect(summary.mean).toBe(6);
    expect(summary.minimum).toBe(5.9);
    expect(summary.maximum).toBe(6.1);
    expect(summary.analyticsState).toBe("READY");
    expect(summary).not.toHaveProperty("timeInRange");
    const today = (await (await call("/api/me/today", a.token)).json()) as any;
    expect(today.glucose.count).toBe(3);
    const meal = (await (
      await call("/api/me/meals", a.token, {
        id: crypto.randomUUID(),
        category: "lunch",
        consumedAt: measuredAt,
        items: [{ name: "Timeline fixture", quantity: 1, unit: "portion" }],
      })
    ).json()) as any;
    const events = (await (
      await call("/api/me/timeline?limit=2", a.token)
    ).json()) as any;
    expect(events.items).toHaveLength(2);
    expect(events.supportedDomains).toEqual(["meal", "glucose"]);
    expect(events.items[0].recordId).toBe(meal.id);
    expect(events.nextCursor).toBeTruthy();
    const second = (await (
      await call(
        `/api/me/timeline?limit=2&cursor=${events.nextCursor}`,
        a.token,
      )
    ).json()) as any;
    expect(second.items).toHaveLength(2);
    expect(
      new Set(
        [...events.items, ...second.items].map(
          (e: any) => e.domain + e.recordId,
        ),
      ).size,
    ).toBe(4);
    const glucoseOnly = (await (
      await call("/api/me/timeline?domain=glucose", a.token)
    ).json()) as any;
    expect(glucoseOnly.items).toHaveLength(3);
    expect(
      (await call("/api/me/timeline?cursor=garbage", a.token)).status,
    ).toBe(400);
    const daily = (await (
      await call("/api/me/summaries/daily", a.token)
    ).json()) as any;
    expect(daily.mealCount).toBe(1);
    expect(daily.glucose.count).toBe(3);
    expect(
      (
        await call(
          `/api/me/glucose/${another.id}`,
          a.token,
          { expectedVersion: 1, reason: "Archive fixture", archived: true },
          "PATCH",
        )
      ).status,
    ).toBe(200);
    const archived = (await (
      await call(
        `/api/me/glucose?archived=true&date=${another.localDate}`,
        a.token,
      )
    ).json()) as any;
    expect(archived.items[0].id).toBe(another.id);
    const after = (await (
      await call("/api/me/glucose/summary", a.token)
    ).json()) as any;
    expect(after.count).toBe(2);
    expect(after.mean).toBeNull();
    await expect(
      Promise.resolve(
        prisma.$executeRaw`UPDATE glucose_observations SET value_mg_dl=123 WHERE id=${record.id}::uuid`,
      ),
    ).rejects.toThrow();
    await call(
      "/api/me/preferences",
      a.token,
      { timezone: "America/New_York" },
      "PATCH",
    );
    const boundary = {
      ...input,
      id: crypto.randomUUID(),
      measuredAt: "2026-03-09T03:30:00Z",
      originalValue: 5.1234,
    };
    const concurrentCreates = await Promise.all([
      call("/api/me/glucose", a.token, boundary),
      call("/api/me/glucose", a.token, boundary),
    ]);
    expect(concurrentCreates.map((r) => r.status)).toEqual([201, 201]);
    const localDay = (await (
      await call("/api/me/glucose?date=2026-03-08", a.token)
    ).json()) as any;
    expect(localDay.items).toHaveLength(1);
    expect(localDay.items[0].localTime).toBe("23:30");
    expect(localDay.items[0].valueMgDl).toBe(92.3031744);
    const dayBefore = (await (
      await call("/api/me/glucose?date=2026-03-09", a.token)
    ).json()) as any;
    expect(dayBefore.items).toHaveLength(0);
    const dstSummary = (await (
      await call("/api/me/glucose/summary?date=2026-03-08", a.token)
    ).json()) as any;
    expect(dstSummary.count).toBe(1);
    expect(dstSummary.mean).toBeNull();
    const page = (await (
      await call("/api/me/glucose?limit=1", a.token)
    ).json()) as any;
    const next = (await (
      await call(`/api/me/glucose?limit=1&cursor=${page.nextCursor}`, a.token)
    ).json()) as any;
    expect(next.items[0].id).not.toBe(page.items[0].id);
    await prisma.sessions.updateMany({
      where: { userId: b.id },
      data: { expiresAt: new Date(Date.now() - 1000) },
    });
    expect((await call("/api/me/glucose", b.token)).status).toBe(401);
    await call("/api/me/consents/withdraw", a.token, {
      purposes: ["descriptive_summaries"],
    });
    expect((await call("/api/me/glucose/summary", a.token)).status).toBe(403);
    expect((await call("/api/me/glucose", a.token)).status).toBe(200);
    await call("/api/me/consents/withdraw", a.token, {
      purposes: ["health_data_processing"],
    });
    expect((await call("/api/me/glucose", a.token)).status).toBe(403);
  } finally {
    await prisma.users.deleteMany({ where: { id: { in: users } } });
  }
}, 30000);
