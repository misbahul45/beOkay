import { afterAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { runChallengeLifecycle } from "../../src/features/community/lifecycle.service.ts";
import { addDays } from "../../src/features/community/lifecycle.model.ts";
import { notificationService } from "../../src/features/notifications/notification.service.ts";

const api = process.env.API_BASE_URL!;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
const J = async (r: Response) => (await r.json()) as any;
const hash = () => (crypto.randomUUID() + crypto.randomUUID()).replace(/-/g, "");
const ALL = ["health_data_processing", "descriptive_summaries", "personalized_ai", "community_membership", "challenge_participation", "leaderboard_visibility"];
const REGION = "35";
const T = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Jakarta" }).format(new Date());
const wib = (date: string, hh = 7) => new Date(`${date}T${String(hh).padStart(2, "0")}:00:00+07:00`);
let alias = 0;

async function actor(purposes = ALL) {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "L", email: `lc-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  const policy = await J(await call("/api/consent-policies/current", token));
  await call("/api/me/consents", token, { policyVersion: policy.version, purposes });
  await call("/api/me/preferences", token, { timezone: "Asia/Jakarta" }, "PATCH");
  return { id, token };
}
async function community(token: string) {
  return (await J(await call(`/api/me/communities?regionCode=${REGION}`, token))).items[0];
}
async function member(token: string, communityId: string) {
  const name = `lcx${"abcdefghij"[alias % 10]}${"klmnopqrst"[Math.floor(alias / 10) % 10]}${crypto.randomUUID().slice(0, 4).replace(/\d/g, (d) => "uvwxyzabcd"[Number(d)]!)}`;
  alias++;
  expect((await call(`/api/me/communities/${communityId}/join`, token, { alias: name })).status).toBeLessThan(300);
}
const session = (userId: string, date: string, minutes = 20) =>
  prisma.activitySession.create({ data: { userId, activityType: "walking", startedAt: wib(date), endedAt: new Date(wib(date).getTime() + minutes * 60_000), durationMinutes: minutes, createHash: hash() } });
const challenge = (communityId: string, startsOn: string, endsOn: string, status: string, targetDays = 3) =>
  prisma.challenge.create({ data: { communityId, title: `Uji ${startsOn}`, description: "Uji siklus", kind: "ACTIVE_DAYS", startsOn: new Date(startsOn + "T00:00:00Z"), endsOn: new Date(endsOn + "T00:00:00Z"), targetDays, scoringVersion: "score-v1", status } });
afterAll(async () => {
  await prisma.users.deleteMany({ where: { id: { in: users } } });
});

test("Siklus: templat membuat periode berjalan dan berikutnya dari tanggal jangkar, idempoten, dengan label status", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor();
  const c = await community(a.token);
  await runChallengeLifecycle();
  expect((await runChallengeLifecycle()).created).toBe(0);
  const weekly = await prisma.challengeTemplate.findUniqueOrThrow({ where: { key: "weekly-active-3" } });
  const rows = await prisma.challenge.findMany({ where: { communityId: c.id, templateId: weekly.id }, orderBy: { startsOn: "asc" } });
  expect(rows).toHaveLength(2);
  expect(rows.map((r) => r.status)).toEqual(["OPEN", "SCHEDULED"]);
  expect(rows.every((r) => r.startsOn.getUTCDay() === 1)).toBe(true);
  expect(rows[0]!.startsOn.toISOString().slice(0, 10) <= T && T <= rows[0]!.endsOn.toISOString().slice(0, 10)).toBe(true);
  await member(a.token, c.id);
  const list = await J(await call(`/api/me/communities/${c.id}/challenges`, a.token));
  const next = list.items.find((x: any) => x.id === rows[1]!.id);
  expect(next).toMatchObject({ status: "SCHEDULED", participantsLabel: "kurang dari 5 peserta", participating: false });
  expect(next.statusLabel).toMatch(/^Mulai (besok|\d+ hari lagi)$/);
  expect((await call(`/api/me/challenges/${rows[1]!.id}/join`, a.token, { leaderboardVisible: false })).status).toBe(201);
});

test("Penutupan: hasil Tuntas, Ikut serta, Keluar; notifikasi hasil dan pengakuan tepat sekali; riwayat dan detail", async () => {
  const [a, b, d] = [await actor(), await actor(), await actor()];
  const c = await community(a.token);
  for (const u of [a, b, d]) await member(u.token, c.id);
  const x = await challenge(c.id, addDays(T, -10), addDays(T, -4), "OPEN");
  for (const u of [a, b, d]) await prisma.challengeParticipant.create({ data: { challengeId: x.id, userId: u.id, leftAt: u === d ? new Date() : null } });
  for (const off of [-9, -8, -7]) await session(a.id, addDays(T, off));
  await session(b.id, addDays(T, -9));
  await runChallengeLifecycle();
  const res = await prisma.challengeParticipant.findMany({ where: { challengeId: x.id } });
  const by = (u: { id: string }) => res.find((r) => r.userId === u.id)!;
  expect([by(a).completionStatus, by(a).finalActiveDays, by(b).completionStatus, by(b).finalActiveDays, by(d).completionStatus]).toEqual(["COMPLETED", 3, "PARTICIPATED", 1, "LEFT"]);
  expect((await prisma.challenge.findUniqueOrThrow({ where: { id: x.id } })).status).toBe("CLOSED");
  await runChallengeLifecycle();
  const notes = await prisma.notification.findMany({ where: { userId: a.id, kind: "CHALLENGE" } });
  expect(notes.map((n) => n.title)).toEqual(["Tantangan selesai: Tuntas"]);
  expect(await prisma.notification.count({ where: { userId: d.id } })).toBe(0);
  expect((await prisma.recognition.findMany({ where: { userId: a.id } })).map((r) => r.key).sort()).toEqual(["CHALLENGE_COMPLETED_1", "CHALLENGE_JOINED_1"]);
  expect(await prisma.notification.count({ where: { userId: a.id, kind: "RECOGNITION" } })).toBe(2);
  const hist = await J(await call("/api/me/challenges/history", a.token));
  expect(hist.items.find((i: any) => i.id === x.id)).toMatchObject({ status: "CLOSED", myResult: { completionStatus: "COMPLETED", label: "Tuntas", finalActiveDays: 3 } });
  const detail = await J(await call(`/api/me/challenges/${x.id}`, b.token));
  expect(detail).toMatchObject({ status: "CLOSED", statusLabel: "Selesai", canJoin: false, canCheckin: false, myResult: { label: "Ikut serta" } });
  expect(detail.rules.join(" ")).toContain("Tidak ada poin untuk intensitas");
  expect((await call(`/api/me/challenges/${x.id}/join`, (await actor()).token, { leaderboardVisible: false })).status).toBe(403);
  expect((await call(`/api/me/challenges/${x.id}/join`, b.token, { leaderboardVisible: false })).status).toBe(409);
});

test("Dimulai: tantangan terjadwal dibuka pada tanggalnya dan peserta yang sudah ikut diberi tahu", async () => {
  const e = await actor();
  const c = await community(e.token);
  await member(e.token, c.id);
  const y = await challenge(c.id, T, addDays(T, 6), "SCHEDULED");
  expect((await call(`/api/me/challenges/${y.id}/join`, e.token, { leaderboardVisible: false })).status).toBe(201);
  await runChallengeLifecycle();
  expect((await prisma.challenge.findUniqueOrThrow({ where: { id: y.id } })).status).toBe("OPEN");
  expect((await prisma.notification.findFirstOrThrow({ where: { userId: e.id, kind: "CHALLENGE" } })).title).toBe("Tantangan dimulai");
});

test("Discovery aman: bukan anggota melihat pratinjau tanpa orang; detail hanya untuk anggota", async () => {
  const n = await actor();
  const list = await J(await call(`/api/me/communities?regionCode=${REGION}`, n.token));
  const item = list.items[0];
  expect(item.myStatus).not.toBe("ACTIVE");
  expect(item.challenges.length).toBeGreaterThan(0);
  for (const ch of item.challenges) {
    expect(Object.keys(ch)).not.toContain("alias");
    expect(ch.participantsLabel).toMatch(/peserta$/);
  }
  expect(JSON.stringify(list)).not.toMatch(/userId|email|lcx/);
  expect((await call(`/api/me/challenges/${item.challenges[0].id}`, n.token)).status).toBe(403);
});

test("Privasi dan hub: sembunyikan dari semua papan peringkat, matikan sorotan Beranda, ringkasan tantangan dan pengakuan", async () => {
  const a = await actor();
  const c = await community(a.token);
  await member(a.token, c.id);
  const open = (await J(await call(`/api/me/communities/${c.id}/challenges`, a.token))).items.find((x: any) => x.status === "OPEN" && x.title === "3 hari aktif minggu ini");
  expect((await call(`/api/me/challenges/${open.id}/join`, a.token, { leaderboardVisible: true })).status).toBe(201);
  expect((await J(await call("/api/me/community/privacy", a.token))).visibleOn).toEqual([{ challengeId: open.id, title: open.title }]);
  const hidden = await J(await call("/api/me/community/privacy/hide-leaderboards", a.token, {}));
  expect(hidden.visibleOn).toEqual([]);
  expect(hidden.neverShared.join(" ")).toContain("Gula darah");
  let ov = await J(await call("/api/me/community/overview", a.token));
  expect(ov).toMatchObject({ consentRequired: false, highlightsEnabled: true, highlight: { type: "CHALLENGE", challengeId: open.id } });
  expect(ov.challenges[0].progress).toMatchObject({ activeDays: 0 });
  expect(ov.recognitions.map((r: any) => r.key)).toContain("CHALLENGE_JOINED_1");
  await call("/api/me/community/privacy", a.token, { highlightsEnabled: false }, "PATCH");
  ov = await J(await call("/api/me/community/overview", a.token));
  expect([ov.highlightsEnabled, ov.highlight]).toEqual([false, null]);
  const none = await actor(["health_data_processing"]);
  expect(await J(await call("/api/me/community/overview", none.token))).toMatchObject({ consentRequired: true, challenges: [], highlight: null });
});

test("Notifikasi: pengingat jatuh tempo masuk kotak masuk tepat sekali, dibaca, dibisukan; WebSocket mengirim hello, pong, event, dan menjaga topik", async () => {
  const u = await actor();
  const now = new Date();
  const local = new Intl.DateTimeFormat("en-GB", { timeZone: "Asia/Jakarta", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(now.getTime() - 60_000));
  await prisma.reminder.create({ data: { userId: u.id, kind: "meal", title: "Makan siang", localTime: local, daysOfWeek: [1, 2, 3, 4, 5, 6, 7] } });
  expect((await notificationService.notifyDueReminders(now)).created).toBeGreaterThanOrEqual(1);
  await notificationService.notifyDueReminders(now);
  const inbox = await J(await call("/api/me/notifications", u.token));
  expect(inbox.items).toHaveLength(1);
  expect(inbox.items[0]).toMatchObject({ kind: "REMINDER", title: "Makan siang", body: "Waktunya mencatat makan.", action: "OPEN_LOG", read: false });
  expect(inbox.unread).toBe(1);

  expect((await call("/api/me/realtime", u.token)).status).toBe(426);
  const events: any[] = [];
  const ws = new WebSocket(api.replace(/^http/, "ws") + "/api/me/realtime", { headers: { authorization: `Bearer ${u.token}` } } as any);
  const waitFor = async (type: string) => {
    for (let i = 0; i < 50; i++) {
      const hit = events.find((e) => e.type === type);
      if (hit) return hit;
      await Bun.sleep(40);
    }
    throw new Error(`no ${type}`);
  };
  ws.onmessage = (m) => events.push(JSON.parse(String(m.data)));
  await new Promise((r) => (ws.onopen = r));
  expect(await waitFor("hello")).toMatchObject({ unread: 1 });
  ws.send(JSON.stringify({ type: "ping" }));
  expect(await waitFor("pong")).toBeTruthy();
  ws.send(JSON.stringify({ type: "subscribe", topic: `challenge:${crypto.randomUUID()}` }));
  expect(await waitFor("error")).toMatchObject({ code: "TOPIC_FORBIDDEN" });
  const c = await community(u.token);
  await member(u.token, c.id);
  const open = (await J(await call(`/api/me/communities/${c.id}/challenges`, u.token))).items.find((x: any) => x.status === "OPEN");
  ws.send(JSON.stringify({ type: "subscribe", topic: `challenge:${open.id}` }));
  expect(await waitFor("subscribed")).toMatchObject({ topic: `challenge:${open.id}` });
  await call(`/api/me/challenges/${open.id}/join`, u.token, { leaderboardVisible: true });
  expect((await J(await call(`/api/me/challenges/${open.id}`, u.token))).checkedInToday).toBe(false);
  expect(await waitFor("challenge.progress")).toMatchObject({ challengeId: open.id });
  expect(await waitFor("leaderboard.changed")).toMatchObject({ challengeId: open.id });
  expect((await call(`/api/me/challenges/${open.id}/checkins`, u.token, {})).status).toBe(201);
  expect((await J(await call(`/api/me/challenges/${open.id}`, u.token))).checkedInToday).toBe(true);
  await call(`/api/me/notifications/${inbox.items[0].id}/read`, u.token, {});
  expect(await waitFor("notifications.read")).toMatchObject({ unread: expect.any(Number) });
  ws.close();

  expect((await J(await call("/api/me/notifications/unread-count", u.token))).unread).toBe((await prisma.notification.count({ where: { userId: u.id, readAt: null } })));
  expect((await J(await call("/api/me/notifications/read-all", u.token, {}))).unread).toBe(0);
  const prefs = await J(await call("/api/me/notification-preferences", u.token, { mutedKinds: ["REMINDER"] }, "PATCH"));
  expect(prefs).toMatchObject({ mutedKinds: ["REMINDER"], pushEnabled: true });
  expect(await notificationService.notify(u.id, { kind: "REMINDER", title: "x", body: "y", action: "OPEN_LOG", dedupeKey: "muted-check" })).toBeNull();
  expect((await call("/api/me/notification-preferences", u.token, { mutedKinds: ["SPAM"] }, "PATCH")).status).toBe(400);
  const other = await actor();
  expect((await call(`/api/me/notifications/${inbox.items[0].id}/read`, other.token, {})).status).toBe(404);
  const bad = new WebSocket(api.replace(/^http/, "ws") + "/api/me/realtime");
  const closed = await new Promise<string>((r) => {
    bad.onerror = () => r("error");
    bad.onclose = () => r("closed");
    bad.onopen = () => r("open");
  });
  expect(closed).not.toBe("open");
  const exp = await J(await call("/api/me/export", u.token));
  expect(exp.data.notifications.length).toBeGreaterThan(0);
});

test("Asisten: menemukan tantangan di komunitasmu, menjelaskan aturan, dan meminta persetujuan bila belum ada", async () => {
  const a = await actor();
  const c = await community(a.token);
  await member(a.token, c.id);
  const say = async (token: string, text: string) => J(await call(`/api/me/conversations/${crypto.randomUUID()}/messages`, token, { clientMessageId: crypto.randomUUID(), text }));
  const r = await say(a.token, "Tantangan apa yang bisa aku ikuti?");
  expect(r.assistantMessage.route).toBe("COMMUNITY");
  const part = r.assistantMessage.parts.find((p: any) => p.type === "challenges");
  expect(part.items.length).toBeGreaterThan(0);
  expect(part.items.every((i: any) => i.participating === false && i.communityName === c.name)).toBe(true);
  expect(await prisma.challengeParticipant.count({ where: { userId: a.id } })).toBe(0);
  const rules = await say(a.token, "Bagaimana aturan tantangan dihitung?");
  expect(rules.assistantMessage.parts[0].text).toContain("hari aktif");
  const none = await actor(["health_data_processing"]);
  const r2 = await say(none.token, "Tantangan apa yang bisa aku ikuti?");
  expect(r2.assistantMessage.parts.some((p: any) => p.type === "consent_required")).toBe(true);
});
