import { expect, test } from "bun:test";
import { rateWindow } from "../../src/shared/http/rate-window.ts";

test("jendela geser: penuh setelah batas, terbuka lagi setelah jendela lewat", () => {
  const w = rateWindow(1000, 2);
  expect(w.full("a", 0)).toBe(false);
  w.record("a", 0);
  w.record("a", 100);
  expect(w.full("a", 500)).toBe(true);
  expect(w.full("b", 500)).toBe(false);
  expect(w.full("a", 1001)).toBe(false);
});

test("entri pengguna yang tidak aktif lagi dibersihkan, jadi peta tidak tumbuh tanpa batas", () => {
  const w = rateWindow(1000, 5);
  for (let i = 0; i < 50; i++) w.record(`u${i}`, 0);
  expect(w.size()).toBe(50);
  expect(w.full("lain", 5000)).toBe(false);
  expect(w.size()).toBe(0);
  w.record("x", 6000);
  w.clear("x");
  expect(w.size()).toBe(0);
});
