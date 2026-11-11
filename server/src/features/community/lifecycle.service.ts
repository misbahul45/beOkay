import { env } from "../../config/env.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { localRecordTime } from "../../shared/http/record-schema.ts";
import { logEvent } from "../../shared/http/logger.ts";
import { notificationService } from "../notifications/notification.service.ts";
import { syncScores } from "./community.service.ts";
import { BUSINESS_TIMEZONE, COMPLETION_LABEL, completionFor, periodsToEnsure, statusOn } from "./lifecycle.model.ts";
import { recognitionService } from "./recognition.service.ts";
import { SCORING_VERSION } from "./scoring.model.ts";

const iso = (d: Date) => d.toISOString().slice(0, 10);
const asDate = (s: string) => new Date(s + "T00:00:00Z");
const FRESH_MS = 10 * 60_000;
let lastRun = 0;

export async function runChallengeLifecycle(now = new Date()) {
  const today = localRecordTime(now, BUSINESS_TIMEZONE).localDate;
  const [templates, communities] = await Promise.all([prisma.challengeTemplate.findMany({ where: { enabled: true } }), prisma.community.findMany({ select: { id: true } })]);
  const rows = templates.flatMap((t) =>
    periodsToEnsure({ durationDays: t.durationDays, targetDays: t.targetDays, cadenceDays: t.cadenceDays, anchorDate: iso(t.anchorDate) }, today).flatMap((p) =>
      communities.map((c) => ({ communityId: c.id, templateId: t.id, title: t.title, description: t.description, kind: t.kind, startsOn: asDate(p.startsOn), endsOn: asDate(p.endsOn), targetDays: t.targetDays, scoringVersion: SCORING_VERSION, status: statusOn(p, today) === "CLOSED" ? "OPEN" : statusOn(p, today) })),
    ),
  );
  const created = rows.length ? (await prisma.challenge.createMany({ data: rows, skipDuplicates: true })).count : 0;

  const opening = await prisma.challenge.findMany({ where: { status: "SCHEDULED", startsOn: { lte: asDate(today) } }, select: { id: true, title: true } });
  let opened = 0;
  for (const c of opening) {
    const moved = await prisma.challenge.updateMany({ where: { id: c.id, status: "SCHEDULED" }, data: { status: "OPEN" } });
    if (moved.count !== 1) continue;
    opened++;
    const parts = await prisma.challengeParticipant.findMany({ where: { challengeId: c.id, leftAt: null }, select: { userId: true } });
    for (const p of parts) await notificationService.notify(p.userId, { kind: "CHALLENGE", title: "Tantangan dimulai", body: `${c.title} dimulai hari ini.`, action: "OPEN_CHALLENGE", refId: c.id, dedupeKey: `challenge-open:${c.id}` });
  }

  const closed = (await prisma.challenge.updateMany({ where: { status: { in: ["OPEN", "SCHEDULED"] }, endsOn: { lt: asDate(today) } }, data: { status: "CLOSED", closedAt: now } })).count;

  let resulted = 0;
  const pending = await prisma.challenge.findMany({ where: { status: "CLOSED", resultsAt: null }, take: 50 });
  for (const c of pending) {
    const parts = await prisma.challengeParticipant.findMany({ where: { challengeId: c.id, completionStatus: null } });
    for (const p of parts) {
      if (p.leftAt) {
        await prisma.challengeParticipant.updateMany({ where: { id: p.id, completionStatus: null }, data: { completionStatus: "LEFT" } });
        continue;
      }
      const s = await syncScores(p.userId, c);
      const status = completionFor(s.activeDays, c.targetDays, false);
      const moved = await prisma.challengeParticipant.updateMany({ where: { id: p.id, completionStatus: null }, data: { completionStatus: status, finalScore: s.score, finalActiveDays: s.activeDays } });
      if (moved.count !== 1) continue;
      resulted++;
      await notificationService.notify(p.userId, { kind: "CHALLENGE", title: `Tantangan selesai: ${COMPLETION_LABEL[status]}`, body: `${c.title}: ${s.activeDays} hari aktif dari target ${c.targetDays}.`, action: "OPEN_CHALLENGE", refId: c.id, dedupeKey: `challenge-result:${c.id}` });
      await recognitionService.refresh(p.userId);
    }
    await prisma.challenge.updateMany({ where: { id: c.id, resultsAt: null }, data: { resultsAt: now } });
  }
  lastRun = Date.now();
  return { today, created, opened, closed, resulted };
}

export async function ensureFreshLifecycle() {
  if (!env.CHALLENGE_LIFECYCLE_ENABLED || Date.now() - lastRun < FRESH_MS) return;
  lastRun = Date.now();
  try {
    await runChallengeLifecycle();
  } catch (e) {
    lastRun = 0;
    logEvent("error", "challenge_lifecycle_failed", { name: e instanceof Error ? e.name : "unknown" });
  }
}

export function startChallengeLifecycle(intervalMs = 60 * 60_000) {
  const tick = async () => {
    try {
      const r = await runChallengeLifecycle();
      if (r.created + r.opened + r.closed + r.resulted > 0) logEvent("info", "challenge_lifecycle", r);
    } catch (e) {
      logEvent("error", "challenge_lifecycle_failed", { name: e instanceof Error ? e.name : "unknown" });
    }
  };
  void tick();
  const timer = setInterval(tick, intervalMs);
  return { stop: () => clearInterval(timer) };
}
