import { afterAll, beforeAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { conversationService } from "../../src/features/conversation/conversation.service.ts";
import { createEducationService } from "../../src/features/education/education.service.ts";
import { applyCuratedDishes } from "../../src/features/food-reference/curated.service.ts";
import { moderationService } from "../../src/features/community/moderation.service.ts";
import { J, actors, api, call, requireIsolatedApi, todayWib } from "../support/api.ts";

const { actor, cleanup } = actors();
const H = ["health_data_processing", "descriptive_summaries"];
const COMMUNITY = ["health_data_processing", "community_membership", "challenge_participation", "leaderboard_visibility"];
const fixtureCodes: string[] = [];
beforeAll(requireIsolatedApi);
afterAll(async () => {
  await prisma.foodReference.deleteMany({ where: { code: { in: fixtureCodes.filter((c) => c.startsWith("CUR")) } } });
  await prisma.foodReference.deleteMany({ where: { code: { in: fixtureCodes } } });
  await cleanup();
});

const send = async (userId: string, text: string): Promise<any> => conversationService.post(userId, crypto.randomUUID(), { clientMessageId: crypto.randomUUID(), text } as any);
const csvCall = (path: string, token: string, csv: string, type = "text/csv") => fetch(api + path, { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": type }, body: csv });
const letters = (n: number) => Array.from(crypto.getRandomValues(new Uint8Array(n)), (b) => "bcdfghjklmnpqrvwxyz"[b % 19]).join("");
const wibParts = (d: Date) => {
  const p = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Jakarta", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(d);
  const g = (t: string) => p.find((x) => x.type === t)!.value;
  return { y: g("year"), m: g("month"), d: g("day"), h: g("hour"), mi: g("minute") };
};
const HEADER = "Device,Serial Number,Device Timestamp,Record Type,Historic Glucose mg/dL,Scan Glucose mg/dL,Notes";
const libreRow = (when: Date, type: 0 | 1, value: number) => {
  const t = wibParts(when);
  return `FreeStyle Libre 2,SN-1,${t.y}-${t.m}-${t.d} ${t.h}:${t.mi},${type},${type === 0 ? value : ""},${type === 1 ? value : ""},`;
};

test("K-4: daftar modul, isi modul, label draf, dan validasi kunci", async () => {
  const a = await actor(H);
  expect((await call("/api/education/modules")).status).toBe(401);
  const list = await J(await call("/api/education/modules", a.token));
  expect(list.includesDrafts).toBe(true);
  expect(list.items.length).toBe(10);
  expect(list.items[0]).toMatchObject({ key: "mengenal-dmt2", reviewStatus: "DRAFT", version: 1 });
  const m = await J(await call("/api/education/modules/hipoglikemia", a.token));
  expect(m.sections.map((s: any) => s.heading)).toContain("Segera cari bantuan bila");
  expect(m.notice).toStartWith("Draf: belum ditinjau klinisi");
  expect((await call("/api/education/modules/tidak-ada", a.token)).status).toBe(404);
  expect((await call("/api/education/modules/BAD_KEY", a.token)).status).toBe(400);
});

test("K-4: produksi hanya menampilkan modul yang sudah ditinjau; versi tinjau tercatat", async () => {
  const prod = createEducationService({ includeDrafts: () => false });
  const before = await prod.list();
  expect(before.items.find((i) => i.key === "label-gizi")).toBeUndefined();
  try {
    await prod.review("label-gizi", 1, "dr. Peninjau Uji");
    const after = await prod.list();
    expect(after.items.find((i) => i.key === "label-gizi")).toMatchObject({ reviewStatus: "REVIEWED" });
    expect((await prod.get("label-gizi")).notice).not.toContain("Draf");
    expect(await prod.forSafety("HEALTH_CLAIM_REQUEST")).toEqual([expect.objectContaining({ key: "label-gizi" })]);
    await expect(prod.review("label-gizi", 1, " ")).rejects.toThrow();
  } finally {
    await prisma.educationModule.update({ where: { key_version: { key: "label-gizi", version: 1 } }, data: { reviewStatus: "DRAFT", reviewedBy: null, reviewedAt: null } });
  }
  const sync = await createEducationService({ includeDrafts: () => true }).sync();
  expect(sync).toMatchObject({ created: 0, rejected: [] });
});

test("K-4: jawaban keselamatan Asisten menautkan modul yang relevan; SELF_HARM tidak", async () => {
  const a = await actor([...H, "personalized_ai"]);
  const med = await send(a.id, "lupa minum metformin tadi pagi, boleh dobel?");
  const parts = med.assistantMessage.parts;
  expect(parts[0]).toMatchObject({ type: "safety", code: "MEDICATION_ADVICE" });
  expect(parts.find((p: any) => p.type === "education").items).toEqual([{ key: "obat-bertanya-dokter", title: "Obat: kapan bertanya ke dokter", readMinutes: 3, reviewStatus: "DRAFT" }]);
  const self = await send(a.id, "aku capek hidup rasanya ingin mati saja");
  expect(self.assistantMessage.parts[0]).toMatchObject({ type: "safety", code: "SELF_HARM" });
  expect(self.assistantMessage.parts.some((p: any) => p.type === "education")).toBe(false);
});

test("K-7: hidangan terkurasi dihitung dari bahan TKPI, punya resep dan porsi, muncul di pencarian dengan label sumber", async () => {
  const a = await actor(H);
  const tag = crypto.randomUUID().slice(0, 4).toUpperCase().replace(/[^A-Z]/g, "Q").padEnd(2, "Q").slice(0, 2);
  const nasi = `${tag}901`, telur = `${tag}902`, minyak = `${tag}903`;
  fixtureCodes.push(nasi, telur, minyak);
  const base = { source: "Tabel Komposisi Pangan Indonesia", sourceVersion: "TKPI 2017", status: "verified_auto" };
  await prisma.foodReference.createMany({
    data: [
      { code: nasi, name: "Nasi uji", nameNormalized: "nasi uji", ...base, water: 56.7, calories: 180, protein: 3, fat: 0.3, carbohydrates: 39.8, fiber: 0.2 },
      { code: telur, name: "Telur uji", nameNormalized: "telur uji", ...base, water: 74.3, calories: 154, protein: 12.4, fat: 10.8, carbohydrates: 0.7, fiber: 0 },
      { code: minyak, name: "Minyak uji", nameNormalized: "minyak uji", ...base, water: 0, calories: 884, protein: 0, fat: 100, carbohydrates: 0, fiber: 0 },
    ],
  });
  const code = `CUR-${tag}`;
  fixtureCodes.push(code);
  const name = `Nasi goreng uji ${tag.toLowerCase()}`;
  const r = await applyCuratedDishes([
    { code, name, serving: { min: 200, typical: 260, max: 400 }, ingredients: [[nasi, 200], [telur, 50], [minyak, 10]] },
    { code: `CUR-${tag}X`, name: "Tidak lengkap", serving: { min: 1, typical: 1, max: 1 }, ingredients: [[nasi, 100], ["ZZ999", 10]] },
  ]);
  expect(r).toEqual({ applied: [code], skipped: [{ code: `CUR-${tag}X`, missing: ["ZZ999"] }] });
  const row = await prisma.foodReference.findUniqueOrThrow({ where: { code }, include: { recipeItems: { orderBy: { position: "asc" } } } });
  expect(row).toMatchObject({ status: "curated", sourceVersion: "curated-dishes-v1", flags: ["needs_dietitian_review"] });
  expect(row.calories!.toNumber()).toBe(Math.round(((360 + 77 + 88.4) / 260) * 1000) / 10);
  expect(row.recipeItems.map((i) => i.grams.toNumber())).toEqual([200, 50, 10]);
  expect(row.method).toContain("belum ditinjau ahli gizi");
  await applyCuratedDishes([{ code, name, serving: { min: 200, typical: 260, max: 400 }, ingredients: [[nasi, 200], [telur, 50], [minyak, 10]] }]);
  expect(await prisma.foodRecipeItem.count({ where: { foodId: row.id } })).toBe(3);

  const found = await J(await call(`/api/me/foods/reference?q=${encodeURIComponent(name)}`, a.token));
  const hit = found.items.find((i: any) => i.code === code);
  expect(hit).toMatchObject({ verification: "curated", provenance: "Kurasi beOkay · dari bahan TKPI", source: "Kurasi beOkay (resep standar dari bahan TKPI)", serving: { minGrams: 200, typicalGrams: 260, maxGrams: 400 } });
  expect(hit.note).toContain("TKPI 2017");
});

test("K-8: tautan pendamping butuh persetujuan terpisah, hanya ringkasan, bisa dicabut, berhenti saat persetujuan ditarik", async () => {
  const a = await actor([...H, "companion_sharing"]), b = await actor(H);
  expect((await call("/api/me/companions", b.token, { label: "Anak", confirm: true })).status).toBe(403);
  expect((await call("/api/me/companions", a.token, { label: "Anak" })).status).toBe(400);

  const today = todayWib();
  const reg = await J(await call("/api/me/medications", a.token, { id: crypto.randomUUID(), name: "Obat rahasia uji" }));
  await call(`/api/me/medications/${reg.id}/schedules`, a.token, { id: crypto.randomUUID(), localTime: "00:01", timezone: "Asia/Jakarta", daysOfWeek: [1, 2, 3, 4, 5, 6, 7], effectiveFrom: new Date(Date.parse(today + "T00:00:00Z") - 3 * 86_400_000).toISOString().slice(0, 10) });
  await call("/api/me/glucose", a.token, { id: crypto.randomUUID(), originalValue: 187, originalUnit: "mg/dL", measuredAt: new Date(Date.now() - 3600_000).toISOString() });
  await call("/api/me/activities", a.token, { id: crypto.randomUUID(), activityType: "walking", startedAt: new Date(Date.now() - 7200_000).toISOString(), durationMinutes: 25 });

  const link = await J(await call("/api/me/companions", a.token, { label: "Anak", confirm: true }));
  expect(link).toMatchObject({ label: "Anak", active: true });
  const token = link.url.split("/c/")[1];
  const page = await fetch(`${api}/c/${token}`);
  expect(page.status).toBe(200);
  expect(page.headers.get("content-security-policy")).toContain("default-src 'none'");
  const html = await page.text();
  expect(html).toContain("Ringkasan 7 hari");
  expect(html).toContain("25 menit");
  expect(html).toContain("pukul 00:01");
  expect(html).not.toContain("187");
  expect(html).not.toContain("Obat rahasia uji");
  expect(html).not.toContain("Fixture");
  expect((await J(await call("/api/me/companions", a.token))).items[0]).toMatchObject({ viewCount: 1 });

  expect((await call(`/api/me/companions/${link.id}/revoke`, b.token, {})).status).toBe(404);
  await call(`/api/me/companions/${link.id}/revoke`, a.token, {});
  expect((await fetch(`${api}/c/${token}`)).status).toBe(410);
  expect((await fetch(`${api}/c/not-a-token`)).status).toBe(404);

  const l2 = await J(await call("/api/me/companions", a.token, { label: "Pasangan", confirm: true }));
  await call("/api/me/companions", a.token, { label: "Adik", confirm: true });
  await call("/api/me/companions", a.token, { label: "Kakak", confirm: true });
  expect((await call("/api/me/companions", a.token, { label: "Lagi", confirm: true })).status).toBe(422);
  await call("/api/me/consents/withdraw", a.token, { purposes: ["companion_sharing"] });
  expect((await fetch(`${api}/c/${l2.url.split("/c/")[1]}`)).status).toBe(410);
  expect(await prisma.companionLink.count({ where: { userId: a.id, revokedAt: null } })).toBe(0);
  expect(await prisma.auditEvent.count({ where: { userId: a.id, eventType: { startsWith: "companion_link" } } })).toBeGreaterThanOrEqual(5);
});

test("K-3: impor CSV LibreView, duplikat, urutan tanggal, ringkasan deskriptif, hapus, isolasi", async () => {
  const a = await actor(H), b = await actor(H), none = await actor([]);
  const now = Date.now();
  const lines = [HEADER];
  const values = [60, 100, 150, 200, 260];
  for (let i = 0; i < 100; i++) lines.push(libreRow(new Date(now - (i + 1) * 15 * 60_000), 0, values[i % 5]!));
  lines.push(libreRow(new Date(now - 30 * 60_000), 1, 140));
  lines.push("FreeStyle Libre 2,SN-1,2026-01-01 08:00,6,,,catatan");
  const csv = lines.join("\n");
  expect((await csvCall("/api/me/cgm/imports", none.token, csv)).status).toBe(403);
  expect((await csvCall("/api/me/cgm/imports", a.token, csv, "application/json")).status).toBe(415);
  const first = await csvCall("/api/me/cgm/imports?fileName=libre.csv", a.token, csv);
  expect(first.status).toBe(201);
  expect(await J(first)).toMatchObject({ fileName: "libre.csv", unit: "mg/dL", rowsTotal: 102, rowsAccepted: 101, rowsDuplicate: 0, rowsSkipped: 1, dateOrder: "YMD", device: "FreeStyle Libre 2" });
  const again = await J(await csvCall("/api/me/cgm/imports", a.token, csv));
  expect(again).toMatchObject({ rowsAccepted: 0, rowsDuplicate: 101 });

  const ambiguous = [HEADER, "L,S,03-04-2025 08:00,0,120,,"].join("\n");
  const amb = await csvCall("/api/me/cgm/imports", a.token, ambiguous);
  expect(amb.status).toBe(422);
  expect((await J(amb)).error.code).toBe("CGM_DATE_ORDER_AMBIGUOUS");
  expect(await J(await csvCall("/api/me/cgm/imports?dateOrder=DMY", a.token, ambiguous))).toMatchObject({ rowsAccepted: 1, dateOrder: "DMY" });
  expect((await csvCall("/api/me/cgm/imports", a.token, "x,y\n1,2")).status).toBe(422);

  const s = await J(await call("/api/me/cgm/summary?days=14", a.token));
  expect(s).toMatchObject({ kindUsed: "HISTORIC", readings: 100, sufficient: false, meanMgDl: 154, thresholdsMgDl: { low: 70, high: 180 } });
  expect(s.bands).toEqual({ veryLow: 0, low: 20, inRange: 40, high: 20, veryHigh: 20 });
  expect(s.limitations[0]).toContain("kurang dari 70%");
  expect(s.notice).toContain("Bukan saran dosis");
  expect((await call("/api/me/cgm/summary?days=7", a.token)).status).toBe(400);
  expect((await J(await call("/api/me/cgm/summary", b.token))).readings).toBe(0);

  const list = await J(await call("/api/me/cgm/imports", a.token));
  expect(list.items).toHaveLength(3);
  const firstId = list.items.at(-1).id;
  expect((await call(`/api/me/cgm/imports/${firstId}`, b.token, undefined, "DELETE")).status).toBe(404);
  expect(await J(await call(`/api/me/cgm/imports/${firstId}`, a.token, undefined, "DELETE"))).toEqual({ deleted: true, id: firstId });
  expect(await prisma.cgmReading.count({ where: { userId: a.id } })).toBe(1);
});

async function communityFixture(n: number) {
  const people = [];
  for (let i = 0; i < n; i++) people.push(await actor(COMMUNITY));
  const community = (await J(await call("/api/me/communities?regionCode=31", people[0]!.token))).items[0];
  for (const [i, p] of people.entries()) {
    const r = await call(`/api/me/communities/${community.id}/join`, p.token, { alias: `Uji${letters(8)}${i}` });
    expect(r.status).toBe(201);
  }
  const challenge = (await J(await call(`/api/me/communities/${community.id}/challenges`, people[0]!.token))).items[0];
  const aliases = await prisma.communityMembership.findMany({ where: { communityId: community.id, userId: { in: people.map((p) => p.id) } } });
  return { people, community, challenge, alias: (userId: string) => aliases.find((m) => m.userId === userId)!.alias };
}

test("K-11: lapor alias, sembunyi otomatis setelah 3 pelapor unik, ganti alias memulihkan, antrean tinjau pemilik", async () => {
  const { people, community, challenge, alias } = await communityFixture(5);
  const [target, r1, r2, r3, r4] = people as [any, any, any, any, any];
  const outsider = await actor(COMMUNITY);
  const report = (who: any, a: string, reason = "ABUSIVE") => call(`/api/me/challenges/${challenge.id}/reports`, who.token, { alias: a, reason });

  expect((await report(outsider, alias(target.id))).status).toBe(403);
  expect((await report(target, alias(target.id))).status).toBe(422);
  expect((await report(r1, "TidakAda")).status).toBe(404);
  expect((await report(r1, alias(target.id), "BOHONG")).status).toBe(400);
  expect(await J(await report(r1, alias(target.id)))).toMatchObject({ reported: true, duplicate: false });
  expect(await J(await report(r1, alias(target.id), "SPAM"))).toMatchObject({ duplicate: true });
  await report(r2, alias(target.id), "IMPERSONATION");
  const m0 = await prisma.communityMembership.findFirstOrThrow({ where: { userId: target.id, communityId: community.id } });
  expect(m0.hiddenAt).toBeNull();
  await report(r3, alias(target.id), "SPAM");
  const m1 = await prisma.communityMembership.findUniqueOrThrow({ where: { id: m0.id } });
  expect(m1.hiddenAt).not.toBeNull();
  expect(await prisma.notification.count({ where: { userId: target.id, kind: "COMMUNITY" } })).toBe(1);
  const mine = await J(await call("/api/me/communities/mine", target.token));
  expect(mine.items.find((i: any) => i.communityId === community.id).aliasHidden).toBe(true);

  const queue = await moderationService.queue();
  expect(queue.find((q) => q.membershipId === m0.id)).toMatchObject({ reports: 3, hidden: true, reasons: { ABUSIVE: 1, IMPERSONATION: 1, SPAM: 1 } });

  const renamed = `Baru${letters(8)}`;
  expect((await call(`/api/me/communities/${community.id}/alias`, target.token, { alias: renamed }, "PATCH")).status).toBe(200);
  expect((await prisma.communityMembership.findUniqueOrThrow({ where: { id: m0.id } })).hiddenAt).toBeNull();
  expect(await prisma.communityReport.count({ where: { membershipId: m0.id, status: "ALIAS_CHANGED" } })).toBe(3);
  expect(await J(await report(r1, renamed))).toMatchObject({ duplicate: false });

  await report(r4, renamed);
  expect((await prisma.communityMembership.findUniqueOrThrow({ where: { id: m0.id } })).hiddenAt).toBeNull();
  await moderationService.resolve(m0.id, "uphold", "Alias menyinggung");
  expect((await prisma.communityMembership.findUniqueOrThrow({ where: { id: m0.id } })).hiddenAt).not.toBeNull();
  expect(await prisma.communityReport.count({ where: { membershipId: m0.id, status: "UPHELD" } })).toBe(2);
  await moderationService.resolve(m0.id, "dismiss", null);
  expect((await prisma.communityMembership.findUniqueOrThrow({ where: { id: m0.id } })).hiddenAt).toBeNull();
});

test("K-11: batas laju aksi komunitas", async () => {
  const { people, community } = await communityFixture(1);
  const p = people[0]!;
  let limited = 0;
  for (let i = 0; i < 31; i++) {
    const r = await call(`/api/me/communities/${community.id}/alias`, p.token, { alias: `Laju${letters(8)}` }, "PATCH");
    if (r.status === 429) limited++;
  }
  expect(limited).toBeGreaterThanOrEqual(1);
});

test("D-6: ekspor FHIR R4 berisi Observation milik pengguna sendiri", async () => {
  const a = await actor(H), b = await actor(H);
  const t = new Date(Date.now() - 3600_000).toISOString();
  await call("/api/me/glucose", a.token, { id: crypto.randomUUID(), originalValue: 7.2, originalUnit: "mmol/L", measuredAt: t, mealContext: "fasting" });
  await call("/api/me/labs", a.token, { id: crypto.randomUUID(), test: "hba1c", value: 7.4, unit: "%", sampledAt: todayWib() });
  await call("/api/me/vitals", a.token, { id: crypto.randomUUID(), kind: "blood_pressure", value: 128, value2: 82, unit: "mmHg", measuredAt: t });
  await call("/api/me/glucose", b.token, { id: crypto.randomUUID(), originalValue: 99, originalUnit: "mg/dL", measuredAt: t });
  expect((await call("/api/me/export/fhir")).status).toBe(401);
  const res = await call("/api/me/export/fhir", a.token);
  expect(res.status).toBe(200);
  expect(res.headers.get("content-type")).toContain("application/fhir+json");
  const bundle = await J(res);
  expect(bundle).toMatchObject({ resourceType: "Bundle", type: "collection" });
  const obs = bundle.entry.map((e: any) => e.resource).filter((r: any) => r.resourceType === "Observation");
  expect(obs).toHaveLength(3);
  expect(obs.find((o: any) => o.code.coding?.[0].code === "41653-7").valueQuantity).toMatchObject({ value: 129.7, unit: "mg/dL" });
  expect(obs.find((o: any) => o.code.coding?.[0].code === "85354-9").component).toHaveLength(2);
  expect(JSON.stringify(bundle)).not.toContain(b.id);
  expect(bundle.entry[0].resource).toMatchObject({ resourceType: "Patient", id: a.id });
  expect(await prisma.auditEvent.count({ where: { userId: a.id, eventType: "data_exported_fhir" } })).toBe(1);
});
