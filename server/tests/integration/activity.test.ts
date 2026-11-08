import { expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";

test("Activity lifecycle persists, corrects, aggregates and isolates accounts", async () => {
  const api = process.env.API_BASE_URL;
  if (!api || process.env.NODE_ENV !== "test")
    throw new Error("Isolated API required");
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
  const json = async (path: string, token: string) =>
    (await call(path, token)).json() as Promise<any>;
  async function actor() {
    const id = crypto.randomUUID(),
      token = crypto.randomUUID();
    users.push(id);
    await prisma.users.create({
      data: {
        id,
        name: "Activity fixture",
        email: `activity-${id}@example.test`,
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
    expect((await call("/api/me/activities")).status).toBe(401);
    expect((await call("/api/me/activities", a.token)).status).toBe(403);
    const policy = await json("/api/consent-policies/current", a.token);
    for (const actor of [a, b])
      expect(
        (
          await call("/api/me/consents", actor.token, {
            policyVersion: policy.version,
            purposes: ["health_data_processing", "descriptive_summaries"],
          })
        ).status,
      ).toBe(200);
    const input = {
      id: crypto.randomUUID(),
      activityType: "walking",
      startedAt: new Date(Date.now() - 3600000).toISOString(),
      durationMinutes: 30,
      notes: "Synthetic session",
    };
    const created = await call("/api/me/activities", a.token, input);
    expect(created.status).toBe(201);
    const row = (await created.json()) as any;
    expect(row.durationMinutes).toBe(30);
    expect(row.steps).toBeNull();
    expect(row.distanceKm).toBeNull();
    expect(
      new Date(row.endedAt).getTime() - new Date(row.startedAt).getTime(),
    ).toBe(1800000);
    const retries = await Promise.all([
      call("/api/me/activities", a.token, input),
      call("/api/me/activities", a.token, input),
    ]);
    expect(retries.map((r) => r.status)).toEqual([201, 201]);
    expect(
      (
        await call("/api/me/activities", a.token, {
          ...input,
          durationMinutes: 31,
        })
      ).status,
    ).toBe(409);
    expect((await json("/api/me/activities", a.token)).items).toHaveLength(1);
    for (const path of [
      `/api/me/activities/${row.id}`,
      `/api/me/activities/${row.id}/revisions`,
    ])
      expect((await call(path, b.token)).status).toBe(404);
    expect(
      (
        await call(
          `/api/me/activities/${row.id}`,
          b.token,
          { expectedVersion: 1, reason: "forged", notes: "denied" },
          "PATCH",
        )
      ).status,
    ).toBe(404);
    const changes = await Promise.all([
      call(
        `/api/me/activities/${row.id}`,
        a.token,
        { expectedVersion: 1, reason: "Correct duration", durationMinutes: 45 },
        "PATCH",
      ),
      call(
        `/api/me/activities/${row.id}`,
        a.token,
        { expectedVersion: 1, reason: "Concurrent edit", durationMinutes: 45 },
        "PATCH",
      ),
    ]);
    expect(changes.map((r) => r.status).sort()).toEqual([200, 409]);
    const updated = await json(`/api/me/activities/${row.id}`, a.token);
    expect(updated.version).toBe(2);
    expect(updated.notes).toBe(input.notes);
    expect(updated.reportedIntensity).toBe("unknown");
    expect(
      new Date(updated.endedAt).getTime() -
        new Date(updated.startedAt).getTime(),
    ).toBe(2700000);
    expect(
      (await json(`/api/me/activities/${row.id}/revisions`, a.token)).items[0]
        .snapshot.durationMinutes,
    ).toBe(30);
    expect(
      (
        await call(
          `/api/me/activities/${row.id}`,
          a.token,
          {
            expectedVersion: 2,
            reason: "Invalid end",
            startedAt: new Date().toISOString(),
          },
          "PATCH",
        )
      ).status,
    ).toBe(422);
    const second = (await (
      await call("/api/me/activities", a.token, {
        ...input,
        id: crypto.randomUUID(),
        distanceKm: 2.5,
        steps: 0,
      })
    ).json()) as any;
    await call("/api/me/activities", a.token, {
      ...input,
      id: crypto.randomUUID(),
      qualityStatus: "needs_review",
      durationMinutes: 20,
    });
    const daily = await json(
      `/api/me/activities/summary?date=${row.localDate}`,
      a.token,
    );
    expect(daily.count).toBe(3);
    expect(daily.durationMinutes).toBe(75);
    expect(daily.eligibleCount).toBe(2);
    expect(daily.distanceKm.coverage).toBe("PARTIAL");
    expect(daily.distanceKm.value).toBe(2.5);
    expect(daily.steps.value).toBe(0);
    const weekly = await json(
      `/api/me/activities/weekly?date=${row.localDate}`,
      a.token,
    );
    expect(weekly.firstDay).toBe(7);
    expect(weekly.days).toHaveLength(7);
    expect(weekly.durationMinutes).toBe(75);
    expect(weekly.activeDays).toBe(1);
    const today = await json("/api/me/today", a.token);
    expect(today.activity.count).toBe(today.date === row.localDate ? 3 : 0);
    expect(
      (await json(`/api/me/summaries/daily?date=${row.localDate}`, a.token))
        .activity.durationMinutes,
    ).toBe(75);
    const events = await json(
      "/api/me/timeline?domain=activity&limit=2",
      a.token,
    );
    expect(events.items).toHaveLength(2);
    expect(events.items[0].domain).toBe("activity");
    expect(events.nextCursor).toBeTruthy();
    const next = await json(
      `/api/me/timeline?domain=activity&limit=2&cursor=${events.nextCursor}`,
      a.token,
    );
    expect(next.items).toHaveLength(1);
    expect(
      new Set([...events.items, ...next.items].map((e: any) => e.recordId))
        .size,
    ).toBe(3);
    expect(
      (
        await call(
          `/api/me/activities/${second.id}`,
          a.token,
          { expectedVersion: 1, reason: "Archive", archived: true },
          "PATCH",
        )
      ).status,
    ).toBe(200);
    expect(
      (
        await json(
          `/api/me/activities?date=${second.localDate}&archived=true`,
          a.token,
        )
      ).items[0].id,
    ).toBe(second.id);
    expect(
      (await json(`/api/me/activities/weekly?date=${row.localDate}`, a.token))
        .durationMinutes,
    ).toBe(45);
    expect(
      (
        await call(
          `/api/me/activities/${second.id}`,
          a.token,
          { expectedVersion: 2, reason: "Restore", archived: false },
          "PATCH",
        )
      ).status,
    ).toBe(200);
    expect(
      (await json(`/api/me/activities/weekly?date=${row.localDate}`, a.token))
        .durationMinutes,
    ).toBe(75);
    await expect(
      Promise.resolve(
        prisma.$executeRaw`UPDATE activity_sessions SET ended_at=started_at WHERE id=${row.id}::uuid`,
      ),
    ).rejects.toThrow();
    await call(
      "/api/me/preferences",
      a.token,
      { timezone: "America/New_York" },
      "PATCH",
    );
    await call("/api/me/activities", a.token, {
      ...input,
      id: crypto.randomUUID(),
      startedAt: "2026-03-09T03:30:00Z",
      durationMinutes: 60,
    });
    expect(
      (await json("/api/me/activities/summary?date=2026-03-08", a.token))
        .durationMinutes,
    ).toBe(60);
    expect(
      (await json("/api/me/activities/summary?date=2026-03-09", a.token))
        .durationMinutes,
    ).toBeNull();
    const dst = await json(
      "/api/me/activities/weekly?date=2026-03-11",
      a.token,
    );
    expect(dst.startDate).toBe("2026-03-08");
    expect(dst.days[0].durationMinutes).toBe(60);
    await call("/api/me/consents/withdraw", a.token, {
      purposes: ["descriptive_summaries"],
    });
    expect((await call("/api/me/activities/weekly", a.token)).status).toBe(403);
    expect((await call("/api/me/activities", a.token)).status).toBe(200);
    await prisma.sessions.updateMany({
      where: { userId: b.id },
      data: { expiresAt: new Date(Date.now() - 1000) },
    });
    expect((await call("/api/me/activities", b.token)).status).toBe(401);
    await call("/api/me/consents/withdraw", a.token, {
      purposes: ["health_data_processing"],
    });
    expect((await call("/api/me/activities", a.token)).status).toBe(403);
  } finally {
    await prisma.users.deleteMany({ where: { id: { in: users } } });
  }
}, 30000);
