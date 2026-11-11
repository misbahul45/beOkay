import { afterAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
const J = async (r: Response) => (await r.json()) as any;
const ALL = ["health_data_processing", "community_membership", "challenge_participation", "leaderboard_visibility"];
async function actor(purposes: string[] = ALL) {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "Nama Asli Rahasia", email: `cm-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  const policy = (await (await call("/api/consent-policies/current", token)).json()) as any;
  await call("/api/me/consents", token, { policyVersion: policy.version, purposes });
  await call("/api/me/preferences", token, { timezone: "Asia/Jakarta" }, "PATCH");
  return { id, token };
}
afterAll(async () => { await prisma.users.deleteMany({ where: { id: { in: users } } }); });
const REGION = "73"; // Sulawesi Selatan
/** Waktu mulai sehingga sesi `min` menit sudah selesai sekarang (aktivitas tidak boleh berakhir di masa depan). */
const ago = (days: number, min = 30) => new Date(Date.now() - days * 86_400_000 - (min + 2) * 60_000).toISOString();
const localDate = (d: Date) => new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Jakarta" }).format(d);

async function communityOf(token: string) {
  const list = await J(await call(`/api/me/communities?regionCode=${REGION}`, token));
  return list.items[0];
}
async function challengeOf(token: string, communityId: string) {
  const first = (await J(await call(`/api/me/communities/${communityId}/challenges`, token))).items[0];
  // Tantangan bawaan dimulai pada tanggal migrasi; fixture memundurkannya agar hari-hari lampau ikut dihitung.
  await prisma.$executeRawUnsafe(`UPDATE challenges SET starts_on = current_date - 20 WHERE id = '${first.id}'::uuid`);
  return (await J(await call(`/api/me/communities/${communityId}/challenges`, token))).items[0];
}
async function logWalk(token: string, daysAgo: number, minutes = 30) {
  const res = await call("/api/me/activities", token, { id: crypto.randomUUID(), activityType: "walking", startedAt: ago(daysAgo, minutes), durationMinutes: minutes });
  expect(res.status).toBe(201);
  return (await J(res)).id as string;
}

test("Direktori wilayah: 38 provinsi, tanpa daftar orang, jumlah anggota dikaburkan di bawah kohort minimum", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor();
  expect((await call("/api/regions")).status).toBe(401);
  const regions = await J(await call("/api/regions", a.token));
  expect(regions.items).toHaveLength(38);
  expect(regions.items.every((r: any) => r.level === "PROVINCE" && /^\d{2}$/.test(r.code))).toBe(true);
  expect((await call("/api/me/communities?regionCode=99", a.token)).status).toBe(404);
  expect((await call("/api/me/communities?regionCode=abc", a.token)).status).toBe(400);
  const c = await communityOf(a.token);
  expect(c).toMatchObject({ myStatus: "NONE" });
  expect(Object.keys(c).sort()).toEqual(["description", "id", "memberCount", "memberCountLabel", "myStatus", "name"]);
  expect(JSON.stringify(c)).not.toMatch(/"userId"|"email"|"alias"/);
});

test("Keanggotaan sukarela: butuh consent, alias divalidasi dan unik, nama asli tidak bocor, keluar menghapus tampilan", async () => {
  const a = await actor(), b = await actor(), noConsent = await actor(["health_data_processing"]);
  const c = await communityOf(a.token);
  expect((await call(`/api/me/communities/${c.id}/join`, noConsent.token, { alias: "Sehat Selalu" })).status).toBe(403);
  expect((await call(`/api/me/communities/${c.id}/join`, a.token, { alias: "a@b.com" })).status).toBe(422);
  expect((await call(`/api/me/communities/${c.id}/join`, a.token, { alias: "Admin Resmi" })).status).toBe(422);
  const al = `Sehat ${crypto.randomUUID().slice(0, 6).replace(/\d/g, (d) => "ghijklmnop"[Number(d)]!)}`;
  const joined = await call(`/api/me/communities/${c.id}/join`, a.token, { alias: al });
  expect(joined.status).toBe(201);
  expect((await call(`/api/me/communities/${c.id}/join`, a.token, { alias: al })).status).toBe(200); // idempoten
  // Alias unik per komunitas, tanpa membedakan huruf besar/kecil.
  expect((await call(`/api/me/communities/${c.id}/join`, b.token, { alias: al.toUpperCase() })).status).toBe(409);
  expect((await J(await call("/api/me/communities/mine", a.token))).items[0]).toMatchObject({ alias: al });
  // Daftar komunitas hanya menampilkan statusku, tidak ada nama asli/alias orang lain.
  const listed = JSON.stringify(await J(await call(`/api/me/communities?regionCode=${REGION}`, b.token)));
  expect(listed).not.toContain(al);
  expect(listed).not.toContain("Nama Asli Rahasia");

  // Konsistensi: tantangan hanya untuk anggota.
  expect((await call(`/api/me/communities/${c.id}/challenges`, b.token)).status).toBe(403);
  expect((await call(`/api/me/communities/${c.id}/challenges`, a.token)).status).toBe(200);

  // Penarikan consent keanggotaan: keanggotaan tidak ditampilkan lagi.
  await call("/api/me/consents/withdraw", a.token, { purposes: ["community_membership"] });
  expect(await J(await call("/api/me/communities/mine", a.token))).toMatchObject({ items: [], consentRequired: true });
  expect((await call(`/api/me/communities/${c.id}/challenges`, a.token)).status).toBe(403);
  // Keluar selalu boleh, bahkan tanpa consent.
  expect((await J(await call(`/api/me/communities/${c.id}/leave`, a.token, {}))).left).toBe(true);
  expect((await prisma.communityMembership.findFirstOrThrow({ where: { userId: a.id } })).status).toBe("LEFT");
});

test("Tantangan: ikut butuh keanggotaan + dua consent; hari aktif dihitung sekali; check-in sukarela idempoten; tidak ada akun lain di progres", async () => {
  const a = await actor(), outsider = await actor();
  const c = await communityOf(a.token);
  await call(`/api/me/communities/${c.id}/join`, a.token, { alias: `Jalan ${crypto.randomUUID().slice(0, 6).replace(/\d/g, (d) => "ghijklmnop"[Number(d)]!)}` });
  const ch = await challengeOf(a.token, c.id);
  expect(ch).toMatchObject({ kind: "ACTIVE_DAYS", targetDays: 20, scoringVersion: "score-v1", participating: false });
  expect((await call(`/api/me/challenges/${ch.id}/join`, outsider.token, {})).status).toBe(403); // bukan anggota
  const noChal = await actor(["health_data_processing", "community_membership"]);
  expect((await call(`/api/me/challenges/${ch.id}/join`, noChal.token, {})).status).toBe(403); // tanpa consent tantangan
  expect((await call(`/api/me/challenges/${ch.id}/join`, a.token, { leaderboardVisible: true, extra: 1 })).status).toBe(400);

  await logWalk(a.token, 0); // hari ini
  const joined = await call(`/api/me/challenges/${ch.id}/join`, a.token, {});
  expect(joined.status).toBe(201);
  expect((await J(joined)).progress).toMatchObject({ activityDays: 1, checkinDays: 0 });

  await logWalk(a.token, 0); // sesi kedua pada hari yang sama: tetap satu hari
  const p1 = await J(await call(`/api/me/challenges/${ch.id}/progress`, a.token));
  expect(p1).toMatchObject({ activityDays: 1, scoringVersion: "score-v1" });
  expect(p1.score).toBe(22.5);
  expect(p1.note).toContain("bukan kegagalan");

  // Check-in: sukarela, idempoten, ada batas mundur dan tidak boleh di masa depan.
  const today = localDate(new Date());
  const yesterday = localDate(new Date(Date.now() - 86_400_000));
  const ck = await J(await call(`/api/me/challenges/${ch.id}/checkins`, a.token, { localDate: yesterday }));
  expect(ck).toMatchObject({ created: true, localDate: yesterday });
  expect((await J(await call(`/api/me/challenges/${ch.id}/checkins`, a.token, { localDate: yesterday }))).created).toBe(false);
  expect((await call(`/api/me/challenges/${ch.id}/checkins`, a.token, { localDate: localDate(new Date(Date.now() + 3 * 86_400_000)) })).status).toBe(422);
  expect((await call(`/api/me/challenges/${ch.id}/checkins`, a.token, { localDate: localDate(new Date(Date.now() - 10 * 86_400_000)) })).status).toBe(422);
  expect(await prisma.challengeCheckin.count({ where: { userId: a.id } })).toBe(1);
  expect(today).toBeTruthy();
  const p2 = await J(await call(`/api/me/challenges/${ch.id}/progress`, a.token));
  expect(p2.checkinDays).toBe(1);
  const period = Math.round((Date.parse(ch.endsOn) - Date.parse(ch.startsOn)) / 86_400_000) + 1;
  expect(p2.score).toBeCloseTo(22.5 + 30 / period, 1);
  expect(JSON.stringify(p2)).not.toMatch(/glucose|glukosa|medication|obat/i);
  // Orang lain tidak punya progres di tantangan ini.
  expect((await call(`/api/me/challenges/${ch.id}/progress`, outsider.token)).status).toBe(409);
});

test("Koreksi sumber: arsip aktivitas membalik poin (append-only) dan memulihkan menambah baris baru; buku besar tidak dapat diubah", async () => {
  const a = await actor();
  const c = await communityOf(a.token);
  await call(`/api/me/communities/${c.id}/join`, a.token, { alias: `Koreksi ${crypto.randomUUID().slice(0, 5)}` });
  const ch = await challengeOf(a.token, c.id);
  const sid = await logWalk(a.token, 0);
  await call(`/api/me/challenges/${ch.id}/join`, a.token, {});
  expect((await J(await call(`/api/me/challenges/${ch.id}/progress`, a.token))).score).toBe(22.5);

  const archive = await call(`/api/me/activities/${sid}`, a.token, { expectedVersion: 1, reason: "Salah catat", archived: true }, "PATCH");
  expect(archive.status).toBe(200);
  const after = await J(await call(`/api/me/challenges/${ch.id}/progress`, a.token));
  expect(after.score).toBe(0);
  expect(after.activityDays).toBe(0);
  expect(after.ledger.filter((e: any) => e.reversalOf).length).toBe(2); // hari aktif + partisipasi dibalik
  expect(after.ledger.length).toBe(4); // 2 asli + 2 pembalikan: tidak ada yang dihapus
  // Pembaruan langsung ke baris buku besar ditolak oleh basis data.
  const bad = async (sql: string) => { try { await prisma.$executeRawUnsafe(sql); return false; } catch { return true; } };
  expect(await bad(`UPDATE score_events SET points = 99 WHERE user_id = '${a.id}'::uuid`)).toBe(true);
  // Sinkron ulang tidak menambah apa pun (idempoten).
  const again = await J(await call(`/api/me/challenges/${ch.id}/progress`, a.token));
  expect(again.ledger.length).toBe(4);
  // Dipulihkan: poin kembali lewat baris asli baru (kunci #2).
  const restore = await call(`/api/me/activities/${sid}`, a.token, { expectedVersion: 2, reason: "Salah arsip", archived: false }, "PATCH");
  expect(restore.status).toBe(200);
  const back = await J(await call(`/api/me/challenges/${ch.id}/progress`, a.token));
  expect(back.score).toBe(22.5);
  expect(back.ledger.length).toBe(6);
});

test("Keadilan: aktivitas manual dihitung, sesi < 10 menit dan needs_review tidak, hari istirahat tidak menurunkan skor", async () => {
  const a = await actor();
  const c = await communityOf(a.token);
  await call(`/api/me/communities/${c.id}/join`, a.token, { alias: `Adil ${crypto.randomUUID().slice(0, 5)}` });
  const ch = await challengeOf(a.token, c.id);
  await logWalk(a.token, 0, 5); // terlalu singkat
  const review = await call("/api/me/activities", a.token, { id: crypto.randomUUID(), activityType: "walking", startedAt: ago(1, 40), durationMinutes: 40, qualityStatus: "needs_review" });
  expect(review.status).toBe(201);
  await call(`/api/me/challenges/${ch.id}/join`, a.token, {});
  const p = await J(await call(`/api/me/challenges/${ch.id}/progress`, a.token));
  expect(p).toMatchObject({ activityDays: 0, score: 0 });
  await logWalk(a.token, 2, 20); // tiga hari lalu bolong di antaranya: tidak ada penalti
  const q = await J(await call(`/api/me/challenges/${ch.id}/progress`, a.token));
  expect(q.score).toBeGreaterThanOrEqual(p.score);
});

test("Papan peringkat: opt-in tiga lapis, kohort minimum, hanya alias+skor, pencabutan berlaku segera, tanpa data kesehatan", async () => {
  const members = await Promise.all(Array.from({ length: 6 }, () => actor()));
  const [a] = members as [typeof members[0], ...typeof members];
  const c = await communityOf(a.token);
  const ch0 = async (t: string) => challengeOf(t, c.id);
  const aliasOf = (i: number) => `Peserta${i}${crypto.randomUUID().slice(0, 4)}`;
  const aliases: string[] = [];
  for (const [i, m] of members.entries()) {
    aliases[i] = aliasOf(i);
    expect((await call(`/api/me/communities/${c.id}/join`, m.token, { alias: aliases[i] })).status).toBe(201);
  }
  const ch = await ch0(a.token);
  // 4 peserta tampil: di bawah kohort minimum → ditekan, daftar kosong.
  for (const [i, m] of members.slice(0, 4).entries()) {
    for (let d = 0; d <= i; d++) await logWalk(m.token, d);
    expect((await call(`/api/me/challenges/${ch.id}/join`, m.token, { leaderboardVisible: true })).status).toBe(201);
  }
  const small = await J(await call(`/api/me/challenges/${ch.id}/leaderboard`, a.token));
  expect(small).toMatchObject({ suppressed: true, minimumCohort: 5, items: [], visibleCount: null });
  expect(small.me).toMatchObject({ visible: true });
  // Peserta ke-5 tampil: daftar muncul. Peserta ke-6 ikut tetapi TIDAK tampil.
  await logWalk(members[4]!.token, 0);
  await call(`/api/me/challenges/${ch.id}/join`, members[4]!.token, { leaderboardVisible: true });
  await logWalk(members[5]!.token, 0);
  await call(`/api/me/challenges/${ch.id}/join`, members[5]!.token, { leaderboardVisible: false });
  const board = await J(await call(`/api/me/challenges/${ch.id}/leaderboard?limit=3`, a.token));
  expect(board).toMatchObject({ suppressed: false, visibleCount: 5, scoringVersion: "score-v1" });
  expect(board.items).toHaveLength(3);
  expect(board.nextOffset).toBe(3);
  expect(Object.keys(board.items[0]).sort()).toEqual(["alias", "isMe", "rank", "score"]);
  const flat = JSON.stringify(board);
  for (const m of members) expect(flat).not.toContain(m.id);
  expect(flat).not.toContain("Nama Asli Rahasia");
  expect(flat).not.toContain(aliases[5]!); // yang tidak opt-in tidak tampil
  expect(board.items[0].rank).toBe(1);
  expect(board.items[0].alias).toBe(aliases[3]); // paling banyak hari aktif (4)
  const page2 = await J(await call(`/api/me/challenges/${ch.id}/leaderboard?limit=3&offset=3`, a.token));
  expect(page2.items).toHaveLength(2);
  expect(page2.nextOffset).toBeNull();
  // Orang di luar komunitas tidak bisa melihat.
  const outsider = await actor();
  expect((await call(`/api/me/challenges/${ch.id}/leaderboard`, outsider.token)).status).toBe(403);

  // Mematikan visibilitas berlaku segera dan peserta turun di bawah kohort → ditekan lagi.
  await call(`/api/me/challenges/${ch.id}/visibility`, members[4]!.token, { visible: false }, "PATCH");
  expect((await J(await call(`/api/me/challenges/${ch.id}/leaderboard`, a.token))).suppressed).toBe(true);
  await call(`/api/me/challenges/${ch.id}/visibility`, members[4]!.token, { visible: true }, "PATCH");
  expect((await J(await call(`/api/me/challenges/${ch.id}/leaderboard`, a.token))).suppressed).toBe(false);
  // Penarikan consent leaderboard_visibility menghilangkan alias dari papan tanpa menunggu apa pun.
  await call("/api/me/consents/withdraw", members[4]!.token, { purposes: ["leaderboard_visibility"] });
  expect((await J(await call(`/api/me/challenges/${ch.id}/leaderboard`, a.token))).suppressed).toBe(true);
  // Menyalakan lagi butuh consent.
  expect((await call(`/api/me/challenges/${ch.id}/visibility`, members[4]!.token, { visible: true }, "PATCH")).status).toBe(403);
});

test("Keluar komunitas menghentikan partisipasi tantangan dan menghapus tampilan; hapus akun menghapus keanggotaan dan skor", async () => {
  const a = await actor();
  const c = await communityOf(a.token);
  await call(`/api/me/communities/${c.id}/join`, a.token, { alias: `Pergi ${crypto.randomUUID().slice(0, 5)}` });
  const ch = await challengeOf(a.token, c.id);
  await logWalk(a.token, 0);
  await call(`/api/me/challenges/${ch.id}/join`, a.token, { leaderboardVisible: true });
  await call(`/api/me/communities/${c.id}/leave`, a.token, {});
  const part = await prisma.challengeParticipant.findFirstOrThrow({ where: { userId: a.id } });
  expect(part.leftAt).not.toBeNull();
  expect(part.leaderboardVisible).toBe(false);
  expect((await call(`/api/me/challenges/${ch.id}/progress`, a.token)).status).toBe(409);
  // Bergabung kembali dengan alias baru diperbolehkan.
  expect((await call(`/api/me/communities/${c.id}/join`, a.token, { alias: `Kembali ${crypto.randomUUID().slice(0, 5)}` })).status).toBe(201);
  await prisma.users.delete({ where: { id: a.id } });
  expect(await prisma.communityMembership.count({ where: { userId: a.id } })).toBe(0);
  expect(await prisma.scoreEvent.count({ where: { userId: a.id } })).toBe(0);
});

test("Skema komunitas tidak punya hubungan ke data kesehatan (batas privasi)", async () => {
  const cols = (await prisma.$queryRawUnsafe(`SELECT table_name, column_name FROM information_schema.columns WHERE table_name IN ('communities','community_memberships','challenges','challenge_participants','challenge_checkins','score_events','regions')`)) as { table_name: string; column_name: string }[];
  const names = cols.map((c) => c.column_name);
  for (const forbidden of ["diagnosis", "glucose", "medication", "latitude", "longitude", "address", "email", "birth_year"]) expect(names.some((n) => n.includes(forbidden))).toBe(false);
  const fks = (await prisma.$queryRawUnsafe(`SELECT conrelid::regclass::text AS t, confrelid::regclass::text AS ref FROM pg_constraint WHERE contype='f' AND conrelid::regclass::text IN ('communities','community_memberships','challenges','challenge_participants','challenge_checkins','score_events')`)) as { t: string; ref: string }[];
  const health = ["health_profiles", "glucose_observations", "medication_regimens", "meal_logs", "user_profiles"];
  expect(fks.filter((f) => health.includes(f.ref))).toEqual([]);
});
