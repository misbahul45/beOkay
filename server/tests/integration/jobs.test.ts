import { afterAll, beforeAll, expect, test } from "bun:test";
import { randomBytes } from "node:crypto";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { JOBS, claimJob, runTick, type Job } from "../../src/features/jobs/jobs.service.ts";
import { cronAuthorized } from "../../src/features/jobs/jobs.routes.ts";
import { api, requireIsolatedApi } from "../support/api.ts";

const letters = (n: number) => Array.from(randomBytes(n), (b) => "abcdefghijklmnopqrstuvwxyz"[b % 26]).join("");
const names: string[] = [];
beforeAll(requireIsolatedApi);
afterAll(async () => {
  await prisma.jobRun.deleteMany({ where: { name: { in: names } } });
});

test("jobs: satu job hanya berjalan sekali per interval meski tick datang berulang atau bersamaan", async () => {
  const name = `test_${letters(10)}`;
  names.push(name);
  let runs = 0;
  const job: Job = { name, everyMs: 60_000, run: async () => ({ n: ++runs }) };
  const t0 = new Date();
  const [a, b] = await Promise.all([runTick(t0, { jobs: [job] }), runTick(t0, { jobs: [job] })]);
  expect([a.jobs[0]!.ran, b.jobs[0]!.ran].filter(Boolean)).toHaveLength(1);
  expect((await runTick(new Date(t0.getTime() + 30_000), { jobs: [job] })).jobs[0]!.ran).toBe(false);
  const later = await runTick(new Date(t0.getTime() + 61_000), { jobs: [job] });
  expect(later.jobs[0]).toMatchObject({ ran: true, status: "OK", result: { n: 2 } });
  expect(await prisma.jobRun.findUniqueOrThrow({ where: { name } })).toMatchObject({ lastStatus: "OK", lastResult: { n: 2 } });
});

test("jobs: kegagalan dicatat tanpa menghentikan job lain", async () => {
  const bad = `test_${letters(10)}`, good = `test_${letters(10)}`;
  names.push(bad, good);
  const r = await runTick(new Date(), { jobs: [{ name: bad, everyMs: 60_000, run: async () => { throw new TypeError("x"); } }, { name: good, everyMs: 60_000, run: async () => ({ ok: true }) }] });
  expect(r.jobs.map((j) => j.status)).toEqual(["FAILED", "OK"]);
  expect((await prisma.jobRun.findUniqueOrThrow({ where: { name: bad } })).lastResult).toEqual({ error: "TypeError" });
  expect(await claimJob(bad, 60_000, new Date())).toBe(false);
});

test("jobs: job sungguhan untuk antrean, pengingat, dan push berjalan; push dilewati tanpa FCM", async () => {
  const r = await runTick(new Date(Date.now() + 3_600_000), { only: ["outbox_drain", "reminder_inbox", "push_dispatch"] });
  expect(r.jobs.map((j) => j.name)).toEqual(["outbox_drain", "reminder_inbox", "push_dispatch"]);
  expect(r.jobs.every((j) => !j.ran || j.status === "OK")).toBe(true);
  expect(JOBS.map((j) => j.name)).toEqual(["outbox_drain", "reminder_inbox", "push_dispatch", "outcome_sweep", "challenge_lifecycle", "coaching_nudges", "education_sync", "retention"]);
});

test("jobs: rute cron tersembunyi tanpa CRON_SECRET; otorisasi memakai pembanding waktu-konstan", async () => {
  expect((await fetch(`${api}/internal/jobs/tick`)).status).toBe(404);
  expect((await fetch(`${api}/internal/jobs/status`, { headers: { authorization: "Bearer apa-saja-0123456789" } })).status).toBe(404);
  const secret = randomBytes(24).toString("hex");
  const req = (h: Record<string, string>) => new Request("http://x/internal/jobs/tick", { headers: h });
  expect(cronAuthorized(req({ authorization: `Bearer ${secret}` }), secret)).toBe(true);
  expect(cronAuthorized(req({ "x-cron-secret": secret }), secret)).toBe(true);
  expect(cronAuthorized(req({ authorization: `Bearer ${secret}x` }), secret)).toBe(false);
  expect(cronAuthorized(req({}), secret)).toBe(false);
  expect(cronAuthorized(req({ authorization: `Bearer ${secret}` }), undefined)).toBe(false);
});
