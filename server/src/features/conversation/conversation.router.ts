import { classifyFollowUp, classifyIntent, extractQuery } from "../agent/agent.intent.ts";
import { screenRequest } from "../agent/agent.safety.ts";

export const ROUTER_VERSION = "router-v1";

export type StatsDomain = "activity" | "glucose" | "nutrition" | "medication" | "logging";
export type StatsDays = 7 | 14 | 30;

export type Route =
  | { kind: "SAFETY"; code: string; message: string; urgent: boolean }
  | { kind: "GREETING" }
  | { kind: "THANKS" }
  | { kind: "SUPPORT" }
  | { kind: "HELP" }
  | { kind: "STATS"; domain: StatsDomain; days: StatsDays }
  | { kind: "FOLLOW_UP"; follow: "WHY" | "MORE" }
  | { kind: "NO_CONTEXT" }
  | { kind: "ACTIVITY_PLAN" }
  | { kind: "FOOD"; query: string }
  | { kind: "CLARIFY_FOOD" }
  | { kind: "UNKNOWN"; probe: string | null };

export type RouteKind = Route["kind"];

const norm = (s: string) =>
  s
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9\s?-]/g, " ")
    .replace(/\s+/g, " ")
    .trim();

const SELF_HARM = /(bunuh diri|ingin mati|pengen mati|pingin mati|mau mati saja|mengakhiri hidup|menyakiti diri|melukai diri)/;
const SELF_HARM_MESSAGE =
  "Terima kasih sudah bercerita. Kamu tidak harus menghadapinya sendirian. Jika kamu merasa tidak aman sekarang, segera hubungi layanan gawat darurat atau minta orang terdekat menemanimu. Bicara dengan tenaga kesehatan jiwa juga bisa membantu.";

const GREETING = /^(halo|hallo|helo|hai|hi|hey|hello|pagi|siang|sore|malam|selamat (pagi|siang|sore|malam)|assalamualaikum|permisi)\b/;
const GREETING_TAIL = new Set(["beokay", "spark", "asisten", "kak", "min", "semua", "juga", "lagi", "ya", "nih"]);
const THANKS = /(terima ?kasih|makasih|makasi|thanks|thank you|thx|tengkyu|oke makasih)/;
const SUPPORT = /(susah konsisten|sulit konsisten|gak konsisten|ga konsisten|nggak konsisten|tidak konsisten|malas|males|bosan|bosen|gagal terus|selalu gagal|stres|stress|sedih|putus asa|menyerah|nyerah|gak semangat|ga semangat|nggak semangat|tidak semangat|kurang semangat|kewalahan|capek nyatet|capek mencatat)/;
const HELP = /(bisa apa|bisa bantu apa|kamu siapa|siapa kamu|apa itu beokay|bantuan|cara pakai|cara menggunakan|^help$|^tolong$|^menu$)/;

const DOMAINS: [StatsDomain, RegExp][] = [
  ["glucose", /(gula darah|glukosa|\bgula\b|\bgdp\b)/],
  ["medication", /(\bobat|minum obat|jadwal obat)/],
  ["activity", /(aktivitas|olahraga|bergerak|jalan kaki|langkah|latihan)/],
  ["nutrition", /(\bmakan|kalori|karbo|karbohidrat|\bgizi|nutrisi|protein|lemak|serat|energi)/],
  ["logging", /(catatan|mencatat|pencatatan|nyatet)/],
];
const STATS_CUE = /(gimana|bagaimana|berapa|seperti apa|kayak apa|ringkasan|rangkuman|rangkum|statistik|progres|progress|perkembangan|rata-rata|rata rata|total|\bcek\b|\blihat\b|apa kabar|sudah berapa|udah berapa)/;
const SELF = /(\baku\b|\bsaya\b|\bgue\b|\bku\b|(aktivitas|olahraga|darah|glukosa|gula|obat|makan|kalori|catatan)ku\b|\bpunyaku\b)/;
const PERIOD = /(minggu ini|bulan ini|hari ini|kemarin|seminggu|sebulan|\d+ hari|\d+ minggu|dua minggu|satu bulan|1 bulan|terakhir)/;

const FOOD_CUE = /(alternatif|pengganti|\bganti\b|rekomendasi|\bsaran\b|\bpilihan\b|\busul|\bcari|\bmenu\b|\blauk\b|snack|camilan|sarapan|\binfo\b|informasi|kalori|\bgizi\b|kandungan|karbo|nutrisi|\bmakan(an)?\b)/;
const FOOD_STOP = new Set([
  "info", "informasi", "kalori", "gizi", "kandungan", "karbo", "karbohidrat", "nutrisi", "berapa", "enak", "gak", "ga", "nggak", "engga", "tidak",
  "sehat", "itu", "ini", "deh", "sih", "nya", "kah", "apakah", "tentang", "soal", "per", "gram", "100", "kak", "min", "lagi", "ya", "nih", "dong",
  "gimana", "bagaimana", "kalau", "kalo", "boleh", "aman", "ok", "oke", "coba", "tau", "tahu", "lihat", "cek", "mau", "pengen", "pingin", "ingin",
  "punya", "isi", "dalam", "satu", "porsi", "seporsi", "makan", "makanan", "minuman", "minum", "sebutkan", "kasih", "beri", "berikan",
  "lain", "lainnya", "hari", "minggu", "bulan", "sekarang", "nanti", "besok", "pagi", "siang", "sore", "malam", "enaknya", "apa", "yang", "aja", "saja",
]);

export function foodQuery(text: string): string | null {
  const kept = norm(text)
    .replace(/\?/g, " ")
    .split(" ")
    .filter((t) => t.length >= 2 && !FOOD_STOP.has(t))
    .join(" ");
  return kept ? extractQuery(kept) : null;
}

function daysOf(t: string): StatsDays {
  if (/(30 hari|sebulan|bulan ini|1 bulan|satu bulan|\b4 minggu)/.test(t)) return 30;
  if (/(14 hari|2 minggu|dua minggu)/.test(t)) return 14;
  return 7;
}

function statsRoute(t: string): Route | null {
  const domain = DOMAINS.find(([, re]) => re.test(t))?.[0];
  if (!domain) return null;
  const cue = STATS_CUE.test(t);
  const self = SELF.test(t);
  const period = PERIOD.test(t);
  if ((cue && (self || period)) || (self && period)) return { kind: "STATS", domain, days: daysOf(t) };
  return null;
}

export function routeMessage(text: string, ctx: { hasPreviousRun: boolean }): Route {
  const t = norm(text);
  if (SELF_HARM.test(t)) return { kind: "SAFETY", code: "SELF_HARM", message: SELF_HARM_MESSAGE, urgent: true };
  const screen = screenRequest(text);
  if (screen.decision !== "ALLOWED") return { kind: "SAFETY", code: screen.code, message: screen.message, urgent: screen.code === "URGENT_SYMPTOM" };

  let body = t;
  const greet = t.match(GREETING);
  if (greet) {
    body = t.slice(greet[0].length).replace(/^[\s,!.?-]+/, "").trim();
    const rest = body.split(" ").filter((w) => w && !GREETING_TAIL.has(w.replace(/[?!.,]/g, "")));
    if (rest.length === 0) return { kind: "GREETING" };
  }
  const words = body.split(" ").filter(Boolean);
  if (THANKS.test(body) && words.length <= 6) return { kind: "THANKS" };
  if (SUPPORT.test(body)) return { kind: "SUPPORT" };
  if (HELP.test(body)) return { kind: "HELP" };
  const follow = classifyFollowUp(body);
  if (follow) return ctx.hasPreviousRun ? { kind: "FOLLOW_UP", follow } : { kind: "NO_CONTEXT" };
  const stats = statsRoute(body);
  if (stats) return stats;
  if (classifyIntent(body) === "ACTIVITY_PLAN") return { kind: "ACTIVITY_PLAN" };
  if (FOOD_CUE.test(body)) {
    const query = foodQuery(body);
    return query ? { kind: "FOOD", query } : { kind: "CLARIFY_FOOD" };
  }
  const probe = foodQuery(body);
  return { kind: "UNKNOWN", probe: probe && probe.split(" ").length <= 4 && words.length <= 6 ? probe : null };
}
