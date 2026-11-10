# Skema P1 irisan 3 (9 Nov 2026)

Semua tabel: PK UUID `gen_random_uuid()`, `TIMESTAMPTZ`, kolom snake_case, invarian lewat CHECK di SQL migrasi, kepemilikan `user_id` dengan `ON DELETE CASCADE` (kecuali `food_reference`, yang bukan data pengguna).

| Tabel / perubahan | Migrasi | Invarian utama (CHECK) |
|---|---|---|
| `food_preferences` | `20261109050000_food_preferences` | `kind` ∈ allergy/restriction/dislike/preference; allergy & restriction ⇒ `strict`, dislike & preference ⇒ `soft`; panjang `term` 2–40; unik `(user_id, kind, term)`; `version ≥ 1` |
| `reminders` | `20261109060000_reminders` | `kind` ∈ 6 jenis; `local_time` ~ `HH:MM` 24 jam; `days_of_week` 1–7 elemen, subset {1..7}; zona waktu diambil dari pengaturan pengguna saat dihitung (tidak dibekukan) |
| `food_reference` (+ ekstensi `vector`, `pg_trgm`) | `20261109070000_food_reference` | `status` ∈ verified_auto/needs_review; semua zat gizi dalam rentang wajar (energi ≤ 950, lainnya ≤ 100); `verified_auto` ⇒ energi, protein, lemak, karbohidrat tidak NULL; `embedding vector(1024)`; indeks GIN trigram + HNSW cosine |
| `activity_sessions` + `external_id` | `20261109080000_activity_device_import` | `source` ∈ manual/health_connect/apple_health; `quality_status` ∈ user_reported/device_reported/needs_review; manual ⇒ tanpa `external_id` & bukan `device_reported`; impor ⇒ `external_id` wajib & bukan `user_reported`; unik `(user_id, source, external_id)` |
| `push_devices`, `push_deliveries` | `20261109090000_push_devices` | `platform` ∈ android/ios; token unik 20–4096 karakter; `push_deliveries.status` ∈ pending/sent/failed/invalid_token; unik `(reminder_id, device_id, scheduled_at)` (idempotensi pengiriman); cascade dari akun, pengingat, dan perangkat |

Catatan:
- `food_reference.embedding` bertipe `Unsupported("vector(1024)")` di Prisma; diakses dengan SQL mentah berparameter. Indeks HNSW hanya ada di SQL migrasi (muncul sebagai satu baris noise pada `migrate diff`).
- Nilai gizi `food_reference` berasal dari OCR + pemeriksaan konsistensi (Atwater, jumlah proksimat). Baris yang nilainya di luar rentang dikosongkan (bukan dipotong) oleh `sanitizeForStorage` dan ditandai `VALUE_DROPPED_*`.
- Penghitungan aktivitas (ringkasan, tujuan, tren) memakai `ACTIVITY_COUNTED_QUALITY = user_reported + device_reported`; `needs_review` tidak pernah dihitung.
