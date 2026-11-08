# Nutrition API — Slice 2

Semua rute di bawah memakai Better Auth verified bearer session dan purpose consent current `health_data_processing`. Summary dan Today juga memerlukan `descriptive_summaries`. Identitas selalu diturunkan dari sesi. Tidak ada body userId yang diterima. Error wrapper, no-store dan request ID mengikuti API existing.

| Method / path | Request | Respons / aturan |
|---|---|---|
| GET `/api/foods/search?q=...` | 2–80 karakter | Maksimal 20 referensi bersama dan makanan pribadi milik akun aktif; nama case-insensitive |
| POST `/api/me/foods` | FoodInput | 201, buat makanan pribadi; tidak bisa menerbitkan referensi global |
| PATCH `/api/me/foods/:id` | FoodInput penuh | 200, hanya pemilik; snapshot meal lama tidak berubah |
| GET `/api/me/meals` | `date?`, `cursor?`, `limit?` 1–30 default 20, `archived?` true/false | items, nextCursor, timezone; keyset consumedAt DESC/id DESC; tanggal dalam timezone preferensi |
| POST `/api/me/meals` | MealInput | 201; ID UUID stabil dari klien untuk retry. ID+payload sama mengembalikan catatan existing; payload berbeda pada ID sama → 409 |
| GET `/api/me/meals/:id` | UUID | Detail, item snapshot, total/coverage, versi, waktu kejadian dan pencatatan |
| PATCH `/api/me/meals/:id` | expectedVersion, reason, fields opsional | Optimistic correction; previous state disimpan transactionally; full replacement bila items diberikan |
| GET `/api/me/meals/:id/revisions` | UUID | Versi sebelumnya dan alasan; owner/consent tetap wajib |
| GET `/api/me/timeline` | Parameter pagination sama dengan meals | Derived meal events; `supportedDomains:["meal"]`; belum cross-domain timeline penuh |
| GET `/api/me/summaries/daily?date=...` | ISO date opsional, default hari pengguna | Nutrition-only mealCount/totals/coverage/recent/computedAt; current source read, bukan tabel summary persisten |
| GET `/api/me/today` | Existing | Tambahan `nutrition`; metric nutrition AVAILABLE, lainnya belum diimplementasikan; recent meal events |

## FoodInput

`name` 1–120, `source` 1–160, `sourceVersion` opsional/null 1–80, `status` user_reported/estimated. `per100g` memuat calories, carbohydrates, protein, fat, fiber; setiap nilai number ≥0 hingga 10000 dengan maksimal 4 desimal atau null. Satuan: energi kkal, lainnya gram. Endpoint tidak menandai masukan pengguna sebagai clinically verified. Catalog awal tidak di-seed dengan nilai nutrisi rekaan.

## MealInput

```json
{
  "id": "UUID-dibuat-saat-runtime",
  "category": "lunch",
  "consumedAt": "2026-11-08T05:00:00Z",
  "notes": null,
  "items": [
    { "name": "Nama makanan yang dicatat", "quantity": 1, "unit": "portion", "grams": null }
  ]
}
```

Contoh bersifat struktural; ganti ID dengan UUID valid dan timestamp dengan kejadian sebenarnya. category: breakfast/lunch/dinner/snack; consumedAt timestamp ISO dengan offset eksplisit, tahun ≥1900 dan tidak melebihi waktu server +5 menit. notes maksimal 2000; 1–30 items.

Item: name wajib, foodId UUID opsional/null, quantity >0 maksimal 10000 (4 desimal), unit g/portion/piece/ml. `g` menggunakan quantity sebagai gram; grams jika diberikan harus sama. Unit lain memerlukan total grams dan gramsBasis weighed/user_estimate untuk kalkulasi; keduanya nullable. Tidak ada konversi otomatis porsi/mL ke gram. Flutter memberi label perkiraan untuk gram unit non-g. Item tanpa referensi tidak mendapat nilai gizi rekaan.

Koreksi memerlukan `expectedVersion` dan reason 1–300. Patch dapat mengganti category, consumedAt, notes, items atau archived. Dalam items koreksi, `id` merujuk item versi existing; referensi/snapshot lama dipertahankan jika foodId sama atau tidak dikirim. `foodId:null` secara eksplisit melepas referensi. Item baru tanpa id mengambil snapshot katalog saat itu. Nama item bebas dapat dikoreksi; nama snapshot katalog tidak ditulis ulang dari klien. Item yang dihilangkan dari array tidak ada pada versi baru tetapi tetap ada dalam revision lama.

`archived:true` mengecualikan record dari daftar aktif, timeline dan summary. `archived:false` memulihkannya. Tidak ada hard-delete endpoint pada slice ini. Detail arsip tetap owner-scoped.

## Perhitungan dan error

Nutrient = nilai per 100 g × total gram /100 dengan Decimal dan pembulatan 4 desimal. Data hilang tetap null. Setiap total memiliki value, knownItems, totalItems, coverage UNKNOWN/PARTIAL/COMPLETE. Partial adalah jumlah item yang diketahui, bukan estimasi total penuh. Empty daily summary mempunyai mealCount 0 dan nilai nutrient null, analytics INSUFFICIENT_DATA. Daily rows dibaca dalam RepeatableRead; batas hari memakai PostgreSQL AT TIME ZONE, termasuk hari DST 23/25 jam.

401 sesi tidak valid; 403 CONSENT_REQUIRED; 400 VALIDATION_ERROR (termasuk ID/date/portion invalid); 404 MEAL_NOT_FOUND/FOOD_NOT_FOUND/CURSOR_NOT_FOUND tanpa bocor pemilik; 409 VERSION_CONFLICT/IDEMPOTENCY_CONFLICT/INVALID_ITEM_REFERENCE; 413/415 mengikuti wrapper; 500 generik tanpa payload sensitif.

Bruno folder `09 - Nutrition` berisi 16 request (create/search/read/retry/correct/revisions/timeline/summary/negative/archive/restore). Environment bersama `test` hanya berisi baseUrl. Inject sessionToken, restrictedSessionToken (health consent aktif tetapi summary consent tidak), newMealId UUID dan eventTime ISO valid saat runtime. Jangan menyimpan token/password dalam koleksi. CLI dijalankan pada Docker network `beokay-test_default`.
