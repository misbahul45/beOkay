# Referensi Skema Database

> Dibuat dari `server/prisma/schema.prisma` (984 baris, **51 model**) dan 21 migrasi di `server/prisma/migrations/` pada audit 10 November 2026. Dokumen per-domain lama (`identity-consent-profile.md`, `nutrition-schema.md`, `glucose-schema.md`, `activity-schema.md`, `health-tracking-schema.md`, `p1-schema.md`) tetap ada sebagai riwayat; **dokumen ini yang mencakup seluruh tabel sampai P3**.
> Basis data: PostgreSQL 17 (`pgvector/pgvector:pg17`), ekstensi `vector` dan `pg_trgm` (dibuat di migrasi `20261109070000_food_reference`).

## 1. Konvensi

| Konvensi | Penerapan |
|---|---|
| PK | `UUID` dengan default `gen_random_uuid()` (tabel auth memakai `pg_catalog.gen_random_uuid()`) |
| Waktu | `TIMESTAMPTZ(6)`; tanggal murni `DATE` (`start_date`, `period_start`, `local_date`) |
| Ukuran | `NUMERIC`/`Decimal` (gizi `(12,4)`, glukosa mg/dL `(16,7)`); tidak ada `FLOAT` untuk data kesehatan |
| `JSONB` | hanya metadata variabel: `snapshot`, `payload`, `state`, `metrics`, `evaluation`, `content`, `result` |
| Nama | tabel & kolom `snake_case` lewat `@map`. **Pengecualian:** 4 tabel auth (`users`, `sessions`, `accounts`, `verifications`) memakai kolom camelCase hasil generator Better Auth |
| Tidak diketahui | `NULL`, bukan `0` |
| Kepemilikan | setiap tabel domain punya `user_id` (FK ke `users`, umumnya `ON DELETE CASCADE`) |
| Koreksi | kolom `version` + `create_hash` + `archived_at`; riwayat di `record_revisions` |
| Invarian | `CHECK`, indeks unik parsial, dan trigger ditulis di SQL migrasi (tidak bisa diekspresikan di Prisma) |
| Prediksi | tidak disimpan di tabel pengukuran |

Nama model auth di Prisma sengaja `Users/Sessions/Accounts/Verifications` (adapter Better Auth mencari delegate sesuai `modelName`). Relasi balik ke tabel domain di model `Users` ditambahkan **manual**; bila `auth:generate` menimpanya, tambahkan lagi.

## 2. Identitas, consent, audit

| Tabel | Kolom penting | Catatan |
|---|---|---|
| `users` | `name`, `email` (unik), `emailVerified`, `image` | `name` = nama tampilan (satu sumber) |
| `sessions` | `token` (unik), `expiresAt`, `ipAddress`, `userAgent`, `userId` | cascade |
| `accounts` | `providerId`, `accountId`, `password`, token OAuth | kata sandi di-hash oleh Better Auth |
| `verifications` | `identifier`, `value`, `expiresAt` | token verifikasi email / reset |
| `user_profiles` | `birth_year` (CHECK 1900–2100) | 1:1 dengan user |
| `health_profiles` | `diagnosis_status`, `diabetes_type`, `diagnosed_year`, `treatment_context[]`, `data_source='user_reported'`, `eligibility_status` | CHECK: detail diagnosis hanya bila `diagnosed`; `treatment_context` ⊆ enumerasi |
| `user_settings` | `locale`, `timezone`, `glucose_unit`, `text_size`, `reduce_motion` | PK = `user_id`; CHECK `locale IN ('id-ID','en-US')` (API hanya menerima `id-ID`) |
| `consent_records` | `purpose`, `policy_version`, `granted_at`, `withdrawn_at`, `source` | **indeks unik parsial** `(user_id, purpose) WHERE withdrawn_at IS NULL`; CHECK `withdrawn_at ≥ granted_at`; CHECK `consent_records_purpose_valid` di-drop dan dibuat ulang di 4 migrasi (`…100100_consent_personalized_ai`, `…110000_community`, `…130000_ml_registry`, `…140000_p2_outbox_outcomes_conversations`) — **menambah tujuan consent baru selalu butuh migrasi**, selain mengubah `consent.policy.ts` |
| `onboarding_progress` | `intro_seen_at`, `completed_at`, `version` | state *diturunkan*, bukan disimpan |
| `audit_events` | `event_type`, `metadata` JSONB, `occurred_at` | `user_id` boleh NULL, `ON DELETE SET NULL`; indeks `(user_id, occurred_at DESC)` |

## 3. Pencatatan kesehatan

| Tabel | Kolom penting | Invarian |
|---|---|---|
| `food_catalog` | `user_id` (**nullable** = katalog bersama), `name`, `source`, `source_version`, `status`, 5 zat gizi per 100 g | indeks `(user_id, name)` |
| `meal_logs` | `category`, `consumed_at`, `capture_method`, `notes`, `create_hash`, `version`, `archived_at` | indeks `(user_id, consumed_at DESC, id DESC)` untuk kursor |
| `meal_items` | `meal_id`, `food_id` (SET NULL), `name`, `quantity`, `unit`, `grams`, `grams_basis`, **snapshot** `source/source_version/status` + 5 zat gizi | gizi disalin saat dicatat |
| `food_portion_measures` | `(user_id, food_id, label)` unik, `grams`, `basis` | ukuran rumah tangga milik pengguna |
| `glucose_observations` | `value_mg_dl` (kanonik), `original_value/unit`, `measured_at`, `recorded_at`, `received_at`, `meal_context`, `quality_status`, `quality_flags[]`, `source` | CHECK domain nilai dan enumerasi (2 CHECK di migrasi glukosa) |
| `activity_sessions` | `activity_type`, `started_at`, `ended_at`, `duration_minutes`, `distance_km`, `steps`, `reported_intensity`, `source`, `quality_status`, `external_id` | `UNIQUE(user_id, source, external_id)`; CHECK `activity_sessions_valid` |
| `medication_regimens` | `name`, `strength`, `dosage_form`, `dosing_instructions`, `instruction_source`, `start/end_date`, `status` | diisi pengguna; tidak ada logika dosis |
| `medication_schedules` | `local_time`, `timezone`, `days_of_week[]`, `enabled`, `effective_from` | |
| `medication_intakes` | `schedule_id?`, `scheduled_at?`, `taken_at?`, `event_at`, `status`, `medication_snapshot` JSONB | **indeks unik parsial** `medication_intakes_occurrence_key (schedule_id, scheduled_at)` |
| `behavior_goals` | `title`, `goal_type`, `target_value`, `period`, `start/end_date`, `status` | |
| `goal_checkins` | `goal_id`, `event_at`, `status`, `value` | |
| `record_revisions` | satu FK nullable per domain (`meal_id`, `glucose_id`, `activity_id`, `regimen_id`, `intake_id`, `goal_id`, `checkin_id`), `version`, `reason`, `snapshot` | `UNIQUE(<fk>, version)` untuk tiap FK |
| `food_preferences` | `kind`, `term`, `label`, `severity`, `notes` | `UNIQUE(user_id, kind, term)` |
| `reminders` | `kind`, `title`, `local_time`, `days_of_week[]`, `enabled` | |

## 4. Turunan, sinkronisasi, antrean

| Tabel | Fungsi |
|---|---|
| `summary_projections` | cache ringkasan (`kind`, `period_start`, `computation_version`, `coverage_status`, `freshness_status` `CURRENT/STALE`, `analytics_state`, `metrics`); `UNIQUE(user_id, kind, period_start, computation_version)`; boleh dibuang |
| `sync_operations` | kuitansi idempotensi sinkronisasi offline: `UNIQUE(user_id, operation_id)`, `payload_hash`, `domain`, `record_id`, `status`, `result` |
| `outbox_events` | antrean transaksional: `type`, `payload`, **`dedupe_key` unik**, `status` (`PENDING/DONE/DEAD`), `attempts`, `available_at`, `last_error`; indeks `(status, available_at)` |

## 5. Referensi gizi (RAG)

`food_reference` — referensi TKPI: `code` (unik), `name`, `name_normalized`, `source`, `source_version`, `source_ref`, `page`, `chapter`, `status` (`verified_auto` dipakai pencarian; `needs_review` disimpan), `flags[]`, 7 kolom gizi (air, energi, protein, lemak, karbohidrat, serat, abu), `embedding vector(1024)`, `embedding_model`.
Indeks: GIN trigram `food_reference_name_trgm_idx` (kata) dan **HNSW** `food_reference_embedding_idx` (makna, cosine). Kolom `embedding` bertipe `Unsupported` di Prisma, sehingga diakses lewat SQL mentah; indeks HNSW tidak dapat diekspresikan di skema Prisma dan merupakan satu dari sedikit "noise" yang sah pada `prisma migrate diff`.

## 6. Push

| Tabel | Kolom penting |
|---|---|
| `push_devices` | `token` **unik global**, `platform`, `app_version`, `active`, `last_error`, `last_seen_at`; indeks `(user_id, active)` |
| `push_deliveries` | `reminder_id`, `device_id`, `scheduled_at`, `status`, `provider_message_id`, `error_code`; **`UNIQUE(reminder_id, device_id, scheduled_at)`** (buku besar pengiriman) |

## 7. Agen dan rekomendasi (P2)

| Tabel | Fungsi |
|---|---|
| `agent_runs` | satu run: `status`, `intent`, `input_text`, `idempotency_key` (`UNIQUE(user_id, idempotency_key)`), `state` JSONB, `safety_decision`, `tool_calls_used`, `version`, `parent_run_id` + `turn` (CHECK `turn` 1–20 dan `turn=1` bila tanpa induk), `expires_at` |
| `agent_run_events` | peristiwa berurut `UNIQUE(run_id, seq)` — sumber kebenaran SSE |
| `agent_tool_calls` | audit alat: `tool`, `tool_version`, `args_hash` (bukan argumen), `status`, `error_code`, `duration_ms`, `result_size` |
| `recommendations` | `rec_type` (`NUTRITION`/`ACTIVITY`), `status` (`OFFERED/ACCEPTED/REJECTED/EXPIRED/INVALIDATED`), `version`, `payload` JSONB, `policy_version`, `expires_at`, `decided_at` |
| `recommendation_decisions` | kuitansi `UNIQUE(user_id, operation_id)` — satu operasi = satu efek |
| `recommendation_feedback` | `kind` `CONSUMED/NOT_CONSUMED/COMPLETED/SKIPPED` (CHECK), `UNIQUE(user_id, operation_id)` |
| `planned_meals` | **rencana** makan (`recommendation_id` unik, `per100g` JSONB, `status`); bukan konsumsi |
| `activity_plans` | **rencana** aktivitas (`planned_for` DATE, `status`, `linked_session_id`); bukan sesi |
| `recommendation_outcomes` | hasil **terukur** dari catatan nyata: `recommendation_id` unik, `evidence_type` (`meal_item`/`activity_session`), `evidence_id` |
| `personalization_profiles` / `personalization_events` | profil deterministik berversi (`data` JSONB) dan jejak perubahannya `UNIQUE(user_id, version)` |

### Percakapan (3.0 Fase 3)

| Tabel | Fungsi |
|---|---|
| `conversation_threads` | `id` dari klien, `title` (CHECK 1–80), `last_run_id` (FK `agent_runs`, SET NULL; run terakhir yang bisa dilanjutkan "kenapa"/"pilihan lain"), `message_count` (CHECK 0–400), `last_message_at` |
| `conversation_messages` | `seq` (`UNIQUE(thread_id, seq)`), `role` `USER`/`ASSISTANT`; pesan pengguna wajib `client_message_id` (`UNIQUE(user_id, client_message_id)`) dan `text` 1–1000; balasan wajib `reply_to_id` (unik, satu balasan per pesan), `route`, `router_version`; `parts` JSONB array (CHECK `jsonb_typeof`); `run_id` (FK `agent_runs`, SET NULL) |

## 8. Komunitas (P2)

| Tabel | Fungsi |
|---|---|
| `regions` | 38 provinsi (kode 2 digit), di-seed oleh migrasi |
| `communities` | satu per wilayah, di-seed ("Hidup Seimbang <provinsi>") |
| `community_memberships` | `alias`, `alias_key`, `status`; **indeks unik parsial** `(community_id, alias_key) WHERE status='ACTIVE'`; tanpa FK ke data kesehatan |
| `challenges` | `kind='ACTIVE_DAYS'`, `starts_on`, `ends_on`, `target_days`, `scoring_version`, `status` |
| `challenge_participants` | `leaderboard_visible` (default `false`), `left_at` |
| `challenge_checkins` | `UNIQUE(challenge_id, user_id, local_date)` |
| `score_events` | buku besar skor **append-only**: trigger `score_events_no_update` menolak UPDATE; koreksi = baris dengan `reversal_of`; indeks unik parsial `score_events_original_unique` pada `(challenge_id, user_id, event_type, source_key) WHERE reversal_of IS NULL` |

## 9. ML dan intervensi

| Tabel | Fungsi |
|---|---|
| `model_versions` | registri: `model_key`, `version` (`UNIQUE`), `artifact_sha256`, `feature_schema_version`, `status` (`RESEARCH_ONLY/SHADOW/APPROVED/DEPRECATED`), `intended_use`, `training_data_provenance`, `evaluation` JSONB, `endpoint_ref`, `approved_at`, `approval_note` |
| `ml_inference_runs` | audit inferensi: `mode` (`SHADOW`/`LIVE`), `status`, `latency_ms`, `input_bytes`, `top_label`, `top_probability`; **tanpa gambar**; `user_id` `SET NULL`, `model_version_id` `RESTRICT` |
| `intervention_preferences` | per pengguna: jeda, jam tenang (menit), jatah harian/mingguan, `muted_triggers[]` |
| `intervention_decisions` | log keputusan (termasuk "tidak mengintervensi"): `trigger_type`, `option`, `reason`, `policy_version`, `eligibility_status`, `data_coverage`, `delivery_status`, `approval_status`, `content`, `dedupe_key` unik, `response`; **tanpa nilai klinis mentah** |

## 10. Riwayat migrasi (urut)

| # | Migrasi | Isi |
|---|---|---|
| 1 | `20261107211003_auth_init` | tabel Better Auth |
| 2 | `20261107222128_identity_profile_consent` | profil, kesehatan, pengaturan, consent, onboarding, audit + CHECK |
| 3 | `20261108070202_nutrition` | katalog, makan, item, revisi |
| 4 | `20261108110400_glucose` | glukosa |
| 5 | `20261108130338_activity` | aktivitas |
| 6 | `20261109010000_medication_goals` | obat + tujuan |
| 7 | `20261109020000_sync_operations` | kuitansi sinkronisasi |
| 8 | `20261109030000_summary_projections` | cache ringkasan |
| 9 | `20261109040000_food_portion_measures` | ukuran porsi |
| 10 | `20261109050000_food_preferences` | preferensi/alergi |
| 11 | `20261109060000_reminders` | pengingat |
| 12 | `20261109070000_food_reference` | TKPI + `vector` + `pg_trgm` + HNSW |
| 13 | `20261109080000_activity_device_import` | impor perangkat |
| 14 | `20261109090000_push_devices` | push |
| 15 | `20261109100000_agent_recommendations` | agen & rekomendasi |
| 16 | `20261109100100_consent_personalized_ai` | tujuan consent baru |
| 17 | `20261109110000_community` | komunitas + seed + trigger skor |
| 18 | `20261109120000_activity_plans` | rencana aktivitas |
| 19 | `20261109130000_ml_registry` | registri model |
| 20 | `20261109140000_p2_outbox_outcomes_conversations` | outbox, hasil terukur, percakapan |
| 21 | `20261110010000_interventions` | intervensi |
| 22 | `20261110132120_conversations` | thread & pesan percakapan Asisten + CHECK |

## 11. Membuat migrasi baru (ringkas)

Dijalankan **di container**, DB kosong (stack uji): `bun run db:migrate:dev -- --create-only --name <nama>` → tambahkan `CHECK`/indeks parsial lewat SQL → verifikasi `prisma migrate diff`. Sisa selisih yang boleh: default `gen_random_uuid` pada 4 tabel auth, indeks HNSW, dan (menurut audit P3 G-02) 2 FK + 1 indeks unik khusus-SQL. Rincian perintah: [../operations/runbook.md](../operations/runbook.md).
