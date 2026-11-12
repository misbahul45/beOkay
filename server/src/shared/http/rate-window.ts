export type RateWindow = {
  full(key: string, now?: number): boolean;
  record(key: string, now?: number): void;
  clear(key: string): void;
  size(): number;
};

export function rateWindow(windowMs: number, max: number): RateWindow {
  const hits = new Map<string, number[]>();
  let lastSweep = 0;
  const fresh = (key: string, now: number) => {
    const kept = (hits.get(key) ?? []).filter((t) => now - t < windowMs);
    if (kept.length) hits.set(key, kept);
    else hits.delete(key);
    return kept;
  };
  const sweep = (now: number) => {
    if (now - lastSweep < windowMs) return;
    lastSweep = now;
    for (const key of [...hits.keys()]) fresh(key, now);
  };
  return {
    full(key, now = Date.now()) {
      sweep(now);
      return fresh(key, now).length >= max;
    },
    record(key, now = Date.now()) {
      hits.set(key, [...fresh(key, now), now]);
    },
    clear(key) {
      hits.delete(key);
    },
    size: () => hits.size,
  };
}
