export const STATISTICS_VERSION = "stats-v1";
export const INSIGHT_RULES_VERSION = "insight-rules-v1";

export const NUTRIENTS = ["calories", "carbohydrates", "protein", "fat", "fiber"] as const;
export type Nutrient = (typeof NUTRIENTS)[number];
export type Coverage = "COMPLETE" | "PARTIAL" | "UNKNOWN";

export type NutrientDay = { value: number | null; knownItems: number; totalItems: number };

export type StatDay = {
  date: string;
  isoWeekday: number;
  meals: number;
  nutrients: Record<Nutrient, NutrientDay>;
  activityMinutes: number | null;
  activitySessions: number;
  glucose: { value: number; context: string }[];
  med: { scheduled: number; taken: number; skipped: number };
};

export type Range = { start: string; end: string; days: number };

export type Statistic = {
  id: string;
  domain: "logging" | "nutrition" | "activity" | "glucose" | "medication";
  label: string;
  value: number | null;
  unit: string | null;
  category: "OBSERVATION_COUNT" | "DESCRIPTIVE_AGGREGATE";
  state: "READY" | "INSUFFICIENT_DATA";
  range: Range;
  sourceType: string;
  sampleCount: number;
  sampleUnit: string;
  minimumSample: number;
  coverage: { status: Coverage; daysWithData: number; totalDays: number };
  derivation: string;
  comparison: { value: number; range: Range; change: number; direction: "UP" | "DOWN" | "SAME" } | null;
  detail: Record<string, number | null> | null;
  limitations: string[];
  analysisVersion: string;
  computedAt: string;
};

export type InsightAction = "OPEN_TRENDS" | "CREATE_GOAL" | "ASK_COACH" | "LOG_MEAL" | "OPEN_GLUCOSE" | "OPEN_MEDICATION";

export type InsightCard = {
  code: string;
  domain: Statistic["domain"];
  title: string;
  body: string;
  evidence: { label: string; value: string }[];
  statisticIds: string[];
  coverage: { daysWithData: number; totalDays: number };
  actions: InsightAction[];
  rulesVersion: string;
};

export const MIN_NUTRITION_DAYS = 3;
export const MIN_ACTIVE_DAYS_FOR_MEAN = 2;
export const MIN_FASTING_READINGS = 3;
export const MIN_READINGS_FOR_RANGE = 2;
export const MIN_DAYS_FOR_WEEKDAY_PATTERN = 14;
export const MIN_ACTIVE_DAYS_FOR_PATTERN = 4;

const NUTRIENT_META: Record<Nutrient, { label: string; unit: string }> = {
  calories: { label: "Energi tercatat per hari tercatat", unit: "kkal" },
  carbohydrates: { label: "Karbohidrat tercatat per hari tercatat", unit: "g" },
  protein: { label: "Protein tercatat per hari tercatat", unit: "g" },
  fat: { label: "Lemak tercatat per hari tercatat", unit: "g" },
  fiber: { label: "Serat tercatat per hari tercatat", unit: "g" },
};

const round = (n: number, d = 1) => Math.round(n * 10 ** d) / 10 ** d;
const mean = (xs: number[]) => xs.reduce((s, x) => s + x, 0) / xs.length;

export function median(xs: number[]): number | null {
  if (xs.length === 0) return null;
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

export function recorded(d: StatDay) {
  return d.meals > 0 || (d.activityMinutes ?? 0) > 0 || d.glucose.length > 0 || d.med.taken + d.med.skipped > 0;
}

const rangeOf = (days: StatDay[]): Range => ({ start: days[0]!.date, end: days[days.length - 1]!.date, days: days.length });

function coverageOf(have: number, total: number): Coverage {
  return have === 0 ? "UNKNOWN" : have === total ? "COMPLETE" : "PARTIAL";
}

function compare(current: number | null, previous: number | null, prevRange: Range, digits = 1): Statistic["comparison"] {
  if (current === null || previous === null) return null;
  const change = round(current - previous, digits);
  return { value: previous, range: prevRange, change, direction: change > 0 ? "UP" : change < 0 ? "DOWN" : "SAME" };
}

type Base = Omit<Statistic, "analysisVersion" | "computedAt" | "range">;

function nutritionStats(cur: StatDay[], prev: StatDay[], prevRange: Range): Base[] {
  const total = cur.length;
  const mealDays = cur.filter((d) => d.meals > 0);
  const out: Base[] = [
    {
      id: "nutrition.logged_days",
      domain: "nutrition",
      label: "Hari dengan catatan makan",
      value: mealDays.length,
      unit: "hari",
      category: "OBSERVATION_COUNT",
      state: "READY",
      sourceType: "USER_REPORTED_MEALS",
      sampleCount: total,
      sampleUnit: "hari",
      minimumSample: 0,
      coverage: { status: coverageOf(mealDays.length, total), daysWithData: mealDays.length, totalDays: total },
      derivation: "Jumlah tanggal lokal yang punya paling sedikit satu catatan makan yang tidak diarsipkan.",
      comparison: compare(mealDays.length, prev.filter((d) => d.meals > 0).length, prevRange, 0),
      detail: { meals: cur.reduce((s, d) => s + d.meals, 0) },
      limitations: ["Hari tanpa catatan berarti tidak tercatat, bukan tidak makan."],
    },
  ];
  for (const n of NUTRIENTS) {
    const valued = (ds: StatDay[]) => ds.filter((d) => d.meals > 0 && d.nutrients[n].value !== null);
    const days = valued(cur);
    const items = days.reduce((s, d) => ({ known: s.known + d.nutrients[n].knownItems, total: s.total + d.nutrients[n].totalItems }), { known: 0, total: 0 });
    const enough = days.length >= MIN_NUTRITION_DAYS;
    const value = enough ? round(mean(days.map((d) => d.nutrients[n].value!)), n === "calories" ? 0 : 1) : null;
    const prevDays = valued(prev);
    const prevValue = prevDays.length >= MIN_NUTRITION_DAYS ? round(mean(prevDays.map((d) => d.nutrients[n].value!)), n === "calories" ? 0 : 1) : null;
    const limitations = [
      "Rata-rata hanya dari hari yang punya catatan makan; bukan asupan harian sebenarnya.",
      "Item tanpa berat atau tanpa nilai gizi tidak ikut dijumlahkan.",
    ];
    if (items.known < items.total) limitations.push(`Nilai ${NUTRIENT_META[n].label.split(" ")[0]!.toLowerCase()} diketahui untuk ${items.known} dari ${items.total} item.`);
    out.push({
      id: `nutrition.${n}_per_logged_day`,
      domain: "nutrition",
      label: NUTRIENT_META[n].label,
      value,
      unit: NUTRIENT_META[n].unit,
      category: "DESCRIPTIVE_AGGREGATE",
      state: enough ? "READY" : "INSUFFICIENT_DATA",
      sourceType: "USER_REPORTED_MEALS",
      sampleCount: days.length,
      sampleUnit: "hari",
      minimumSample: MIN_NUTRITION_DAYS,
      coverage: { status: items.total === 0 ? "UNKNOWN" : items.known === items.total ? "COMPLETE" : "PARTIAL", daysWithData: days.length, totalDays: total },
      derivation: "Jumlah nilai gizi item per tanggal lokal (gizi per 100 g × gram ÷ 100), lalu dirata-ratakan atas hari yang punya nilai.",
      comparison: compare(value, prevValue, prevRange, n === "calories" ? 0 : 1),
      detail: { knownItems: items.known, totalItems: items.total },
      limitations,
    });
  }
  return out;
}

function activityStats(cur: StatDay[], prev: StatDay[], prevRange: Range): Base[] {
  const total = cur.length;
  const active = (ds: StatDay[]) => ds.filter((d) => (d.activityMinutes ?? 0) > 0);
  const act = active(cur);
  const prevAct = active(prev);
  const minutes = (ds: StatDay[]) => ds.reduce((s, d) => s + (d.activityMinutes ?? 0), 0);
  const anyRecord = cur.some(recorded);
  const sessions = cur.reduce((s, d) => s + d.activitySessions, 0);
  const common = {
    domain: "activity" as const,
    sourceType: "USER_AND_DEVICE_ACTIVITY",
    sampleUnit: "hari",
    coverage: { status: coverageOf(act.length, total), daysWithData: act.length, totalDays: total },
  };
  const noSessions = "Tidak ada sesi tercatat bukan berarti tidak bergerak.";
  return [
    {
      ...common,
      id: "activity.total_minutes",
      label: "Durasi aktivitas tercatat",
      value: act.length ? minutes(cur) : null,
      unit: "menit",
      category: "DESCRIPTIVE_AGGREGATE",
      state: act.length ? "READY" : "INSUFFICIENT_DATA",
      sampleCount: act.length,
      minimumSample: 1,
      derivation: "Jumlah durasi sesi yang dilaporkan sendiri atau diimpor perangkat; sesi yang perlu ditinjau tidak dihitung.",
      comparison: compare(act.length ? minutes(cur) : null, prevAct.length ? minutes(prev) : null, prevRange, 0),
      detail: { sessions },
      limitations: [noSessions],
    },
    {
      ...common,
      id: "activity.active_days",
      label: "Hari aktif tercatat",
      value: anyRecord ? act.length : null,
      unit: "hari",
      category: "OBSERVATION_COUNT",
      state: anyRecord ? "READY" : "INSUFFICIENT_DATA",
      sampleCount: total,
      minimumSample: 1,
      derivation: "Jumlah tanggal lokal dengan paling sedikit satu sesi aktivitas yang dihitung.",
      comparison: compare(anyRecord ? act.length : null, prev.some(recorded) ? prevAct.length : null, prevRange, 0),
      detail: null,
      limitations: [noSessions],
    },
    {
      ...common,
      id: "activity.minutes_per_active_day",
      label: "Rata-rata menit per hari aktif",
      value: act.length >= MIN_ACTIVE_DAYS_FOR_MEAN ? round(minutes(cur) / act.length, 0) : null,
      unit: "menit",
      category: "DESCRIPTIVE_AGGREGATE",
      state: act.length >= MIN_ACTIVE_DAYS_FOR_MEAN ? "READY" : "INSUFFICIENT_DATA",
      sampleCount: act.length,
      minimumSample: MIN_ACTIVE_DAYS_FOR_MEAN,
      derivation: "Total durasi tercatat dibagi jumlah hari aktif tercatat.",
      comparison: compare(
        act.length >= MIN_ACTIVE_DAYS_FOR_MEAN ? round(minutes(cur) / act.length, 0) : null,
        prevAct.length >= MIN_ACTIVE_DAYS_FOR_MEAN ? round(minutes(prev) / prevAct.length, 0) : null,
        prevRange,
        0,
      ),
      detail: null,
      limitations: ["Hari tanpa sesi tidak ikut dibagi."],
    },
  ];
}

function glucoseStats(cur: StatDay[], prev: StatDay[], prevRange: Range, unit: string): Base[] {
  const total = cur.length;
  const all = cur.flatMap((d) => d.glucose);
  const days = cur.filter((d) => d.glucose.length > 0).length;
  const fasting = (ds: StatDay[]) => ds.flatMap((d) => d.glucose.filter((g) => g.context === "fasting").map((g) => g.value));
  const f = fasting(cur);
  const pf = fasting(prev);
  const fMed = f.length >= MIN_FASTING_READINGS ? median(f) : null;
  const pMed = pf.length >= MIN_FASTING_READINGS ? median(pf) : null;
  const digits = unit === "mg/dL" ? 0 : 1;
  const common = {
    domain: "glucose" as const,
    sourceType: "MANUAL_GLUCOMETER",
    sampleUnit: "pengukuran",
    coverage: { status: coverageOf(days, total), daysWithData: days, totalDays: total },
  };
  const point = "Pengukuran jari sesekali tidak menggambarkan kadar sepanjang hari.";
  const noDerived = "Tidak ada Time in Range, GMI, atau perkiraan HbA1c dari data ini.";
  const notClinical = "Ini bukan penilaian klinis.";
  const range = all.length >= MIN_READINGS_FOR_RANGE;
  return [
    {
      ...common,
      id: "glucose.readings",
      label: "Pengukuran glukosa tercatat",
      value: all.length,
      unit: "pengukuran",
      category: "OBSERVATION_COUNT",
      state: "READY",
      sampleCount: all.length,
      minimumSample: 0,
      derivation: "Jumlah pengukuran glukometer manual yang tidak ditandai perlu ditinjau dan tidak diarsipkan.",
      comparison: compare(all.length, prev.reduce((s, d) => s + d.glucose.length, 0), prevRange, 0),
      detail: { daysWithReadings: days },
      limitations: [point],
    },
    {
      ...common,
      id: "glucose.fasting_median",
      label: "Glukosa puasa (median)",
      value: fMed === null ? null : round(fMed, digits),
      unit,
      category: "DESCRIPTIVE_AGGREGATE",
      state: fMed === null ? "INSUFFICIENT_DATA" : "READY",
      sampleCount: f.length,
      minimumSample: MIN_FASTING_READINGS,
      derivation: "Median pengukuran berkonteks puasa; tidak digabung dengan konteks lain.",
      comparison: compare(fMed === null ? null : round(fMed, digits), pMed === null ? null : round(pMed, digits), prevRange, digits),
      detail: null,
      limitations: [point, noDerived, notClinical],
    },
    {
      ...common,
      id: "glucose.observed_range",
      label: "Rentang pengukuran tercatat",
      value: null,
      unit,
      category: "DESCRIPTIVE_AGGREGATE",
      state: range ? "READY" : "INSUFFICIENT_DATA",
      sampleCount: all.length,
      minimumSample: MIN_READINGS_FOR_RANGE,
      derivation: "Nilai terendah dan tertinggi dari pengukuran yang tercatat pada periode ini, semua konteks.",
      comparison: null,
      detail: range ? { min: round(Math.min(...all.map((g) => g.value)), digits), max: round(Math.max(...all.map((g) => g.value)), digits) } : null,
      limitations: [point, "Konteks pengukuran berbeda (puasa, sesudah makan) tidak sebanding.", notClinical],
    },
  ];
}

function medicationStats(cur: StatDay[]): Base[] {
  const sum = (k: keyof StatDay["med"]) => cur.reduce((s, d) => s + d.med[k], 0);
  const scheduled = sum("scheduled");
  const taken = sum("taken");
  const skipped = sum("skipped");
  const unconfirmed = Math.max(0, scheduled - taken - skipped);
  const days = cur.filter((d) => d.med.scheduled > 0).length;
  return [
    {
      id: "medication.confirmed",
      domain: "medication",
      label: "Jadwal obat yang dikonfirmasi",
      value: scheduled ? taken + skipped : null,
      unit: "jadwal",
      category: "OBSERVATION_COUNT",
      state: scheduled ? "READY" : "INSUFFICIENT_DATA",
      sourceType: "USER_CONFIRMED_MEDICATION",
      sampleCount: scheduled,
      sampleUnit: "jadwal",
      minimumSample: 1,
      coverage: { status: scheduled === 0 ? "UNKNOWN" : unconfirmed === 0 ? "COMPLETE" : "PARTIAL", daysWithData: days, totalDays: cur.length },
      derivation: "Kemunculan jadwal dibandingkan konfirmasi yang kamu catat (diminum atau dilewati).",
      comparison: null,
      detail: { scheduled, taken, skipped, unconfirmed },
      limitations: ["Belum dikonfirmasi tidak berarti terlewat.", "Ini catatan, bukan ukuran kepatuhan."],
    },
  ];
}

function loggingStats(cur: StatDay[], prev: StatDay[], prevRange: Range): Base[] {
  const days = cur.filter(recorded).length;
  return [
    {
      id: "logging.recorded_days",
      domain: "logging",
      label: "Hari dengan catatan",
      value: days,
      unit: "hari",
      category: "OBSERVATION_COUNT",
      state: "READY",
      sourceType: "ALL_RECORDS",
      sampleCount: cur.length,
      sampleUnit: "hari",
      minimumSample: 0,
      coverage: { status: coverageOf(days, cur.length), daysWithData: days, totalDays: cur.length },
      derivation: "Tanggal lokal dengan paling sedikit satu catatan makan, aktivitas, glukosa, atau konfirmasi obat.",
      comparison: compare(days, prev.filter(recorded).length, prevRange, 0),
      detail: null,
      limitations: ["Ini tentang kebiasaan mencatat, bukan tentang kesehatanmu."],
    },
  ];
}

const isWeekend = (d: StatDay) => d.isoWeekday >= 6;

export function weekdayPattern(cur: StatDay[]) {
  const weekdays = cur.filter((d) => !isWeekend(d));
  const weekend = cur.filter(isWeekend);
  const activeWd = weekdays.filter((d) => (d.activityMinutes ?? 0) > 0).length;
  const activeWe = weekend.filter((d) => (d.activityMinutes ?? 0) > 0).length;
  if (cur.length < MIN_DAYS_FOR_WEEKDAY_PATTERN || activeWd + activeWe < MIN_ACTIVE_DAYS_FOR_PATTERN || weekdays.length === 0 || weekend.length === 0) return null;
  const wdRate = activeWd / weekdays.length;
  const weRate = activeWe / weekend.length;
  if (Math.abs(wdRate - weRate) < 0.25) return null;
  return { leaning: wdRate > weRate ? ("WEEKDAYS" as const) : ("WEEKEND" as const), activeWeekdays: activeWd, weekdays: weekdays.length, activeWeekend: activeWe, weekendDays: weekend.length };
}

const fmt = (v: number | null, unit: string | null) => (v === null ? "tidak tersedia" : `${String(v).replace(".", ",")}${unit ? " " + unit : ""}`);

export function buildInsightCards(stats: Statistic[], cur: StatDay[], limit = 5): InsightCard[] {
  const by = (id: string) => stats.find((s) => s.id === id)!;
  const cards: InsightCard[] = [];
  const n = cur.length;
  const act = by("activity.total_minutes");
  const actDays = by("activity.active_days");
  if (act.comparison && act.value !== null && act.comparison.value > 0 && Math.abs(act.comparison.change) / act.comparison.value >= 0.1) {
    const up = act.comparison.change > 0;
    cards.push({
      code: "ACTIVITY_PERIOD_CHANGE",
      domain: "activity",
      title: `Durasi aktivitas tercatat ${up ? "lebih tinggi" : "lebih rendah"} dari ${n} hari sebelumnya.`,
      body: up ? "Ini perbandingan dengan catatanmu sendiri." : "Bisa jadi ada sesi yang belum dicatat. Mau cari target yang lebih mudah dijalankan?",
      evidence: [
        { label: `${n} hari ini`, value: `${fmt(act.value, "menit")} · ${actDays.value ?? 0} hari aktif` },
        { label: `${n} hari sebelumnya`, value: fmt(act.comparison.value, "menit") },
      ],
      statisticIds: [act.id, actDays.id],
      coverage: { daysWithData: act.coverage.daysWithData, totalDays: n },
      actions: up ? ["OPEN_TRENDS", "ASK_COACH"] : ["OPEN_TRENDS", "CREATE_GOAL", "ASK_COACH"],
      rulesVersion: INSIGHT_RULES_VERSION,
    });
  }
  const pattern = weekdayPattern(cur);
  if (pattern) {
    const wd = pattern.leaning === "WEEKDAYS";
    cards.push({
      code: "ACTIVITY_WEEKDAY_PATTERN",
      domain: "activity",
      title: `Aktivitas yang kamu catat lebih sering di ${wd ? "hari kerja" : "akhir pekan"}.`,
      body: wd ? "Mau lihat apakah akhir pekan bisa diisi kegiatan ringan yang kamu sukai?" : "Mau cari kegiatan singkat yang muat di hari kerja?",
      evidence: [
        { label: "Hari kerja", value: `${pattern.activeWeekdays} dari ${pattern.weekdays} hari aktif` },
        { label: "Akhir pekan", value: `${pattern.activeWeekend} dari ${pattern.weekendDays} hari aktif` },
      ],
      statisticIds: [actDays.id],
      coverage: { daysWithData: cur.filter(recorded).length, totalDays: n },
      actions: ["OPEN_TRENDS", "ASK_COACH"],
      rulesVersion: INSIGHT_RULES_VERSION,
    });
  }
  const meals = by("nutrition.logged_days");
  if (meals.value !== null && meals.value > 0 && meals.value / n < 0.5) {
    cards.push({
      code: "NUTRITION_LOGGING_COVERAGE",
      domain: "nutrition",
      title: `Catatan makan ada di ${meals.value} dari ${n} hari.`,
      body: "Rata-rata gizi hanya mewakili hari yang tercatat. Mencatat lebih rutin membuat ringkasannya lebih berguna.",
      evidence: [{ label: "Hari dengan catatan makan", value: `${meals.value} dari ${n}` }],
      statisticIds: [meals.id],
      coverage: { daysWithData: meals.value, totalDays: n },
      actions: ["LOG_MEAL"],
      rulesVersion: INSIGHT_RULES_VERSION,
    });
  }
  const fasting = by("glucose.fasting_median");
  if (fasting.comparison && fasting.value !== null) {
    const dir = fasting.comparison.direction;
    cards.push({
      code: "GLUCOSE_FASTING_CONTEXT",
      domain: "glucose",
      title: dir === "SAME" ? "Median glukosa puasa yang kamu catat sama dengan periode sebelumnya." : `Median glukosa puasa yang kamu catat ${dir === "UP" ? "lebih tinggi" : "lebih rendah"} dari periode sebelumnya.`,
      body: "Hanya pengukuran puasa yang dibandingkan. Ini pengamatan, bukan penilaian; bicarakan pola yang mengkhawatirkan dengan tenaga kesehatanmu.",
      evidence: [
        { label: `${n} hari ini`, value: `${fmt(fasting.value, fasting.unit)} · ${fasting.sampleCount} pengukuran` },
        { label: `${n} hari sebelumnya`, value: fmt(fasting.comparison.value, fasting.unit) },
      ],
      statisticIds: [fasting.id],
      coverage: { daysWithData: fasting.coverage.daysWithData, totalDays: n },
      actions: ["OPEN_GLUCOSE"],
      rulesVersion: INSIGHT_RULES_VERSION,
    });
  }
  const med = by("medication.confirmed");
  const unconfirmed = med.detail?.unconfirmed ?? 0;
  if (med.state === "READY" && unconfirmed > 0) {
    cards.push({
      code: "MEDICATION_UNCONFIRMED",
      domain: "medication",
      title: `${unconfirmed} jadwal obat belum dikonfirmasi pada periode ini.`,
      body: "Konfirmasi hanya bila memang sudah kamu lakukan. Belum dikonfirmasi tidak berarti terlewat.",
      evidence: [{ label: "Dikonfirmasi", value: `${med.value} dari ${med.detail?.scheduled ?? 0} jadwal` }],
      statisticIds: [med.id],
      coverage: { daysWithData: med.coverage.daysWithData, totalDays: n },
      actions: ["OPEN_MEDICATION"],
      rulesVersion: INSIGHT_RULES_VERSION,
    });
  }
  return cards.slice(0, limit);
}

export function buildStatistics(all: StatDay[], opts: { glucoseUnit: string; computedAt: Date }) {
  const n = all.length / 2;
  if (!Number.isInteger(n) || n < 1) throw new Error("buildStatistics needs an even, non-empty list of days");
  const prev = all.slice(0, n);
  const cur = all.slice(n);
  const range = rangeOf(cur);
  const prevRange = rangeOf(prev);
  const computedAt = opts.computedAt.toISOString();
  const base = [
    ...loggingStats(cur, prev, prevRange),
    ...nutritionStats(cur, prev, prevRange),
    ...activityStats(cur, prev, prevRange),
    ...glucoseStats(cur, prev, prevRange, opts.glucoseUnit),
    ...medicationStats(cur),
  ];
  const statistics: Statistic[] = base.map((s) => ({ ...s, range, analysisVersion: STATISTICS_VERSION, computedAt }));
  const series = cur.map((d) => ({
    date: d.date,
    recorded: recorded(d),
    meals: d.meals,
    nutrients: Object.fromEntries(
      NUTRIENTS.map((k) => [k, d.meals ? { value: d.nutrients[k].value === null ? null : round(d.nutrients[k].value!, 1), coverage: coverageOf(d.nutrients[k].knownItems, d.nutrients[k].totalItems) } : null]),
    ) as Record<Nutrient, { value: number | null; coverage: Coverage } | null>,
    activityMinutes: d.activityMinutes !== null && d.activityMinutes > 0 ? d.activityMinutes : null,
    glucose: d.glucose,
    medication: d.med,
  }));
  return {
    analysisVersion: STATISTICS_VERSION,
    period: range,
    comparisonPeriod: prevRange,
    analyticsState: cur.some(recorded) ? ("READY" as const) : ("INSUFFICIENT_DATA" as const),
    glucoseUnit: opts.glucoseUnit,
    statistics,
    insights: buildInsightCards(statistics, cur),
    series,
    computedAt,
  };
}
