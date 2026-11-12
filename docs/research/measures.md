# Ukuran keberhasilan dari basis data

> Sejak 3.0 Fase 8. Dihitung oleh `server/scripts/analytics/measures.ts` (`measures-v1`) untuk **kohort pengguna dengan consent `product_analytics` aktif**. Pengguna tanpa consent itu tidak masuk hitungan apa pun di sini. Angka ini untuk evaluasi produk, bukan penilaian klinis individu.

```bash
docker compose -f compose.prod.yaml --env-file .env.prod run --rm api bun run scripts/analytics/measures.ts --days 28
docker compose -f compose.prod.yaml --env-file .env.prod run --rm api bun run scripts/analytics/measures.ts --from 2026-12-01 --to 2027-01-01
```

| Butir gap | Ukuran di [gap analysis](../audits/gap-analysis-2026-11-12.md) | Kunci keluaran | Sumber |
|---|---|---|---|
| D-1 | DAU/WAU, hari-catat per minggu, retensi minggu ke-4 | `engagement.dau`, `engagement.wau`, `engagement.recordDaysPerWeekMedian`, `engagement.week4Retention` | `usage_events` (`record_created` dicatat server); retensi = ada catatan di hari 21–28 sejak akun dibuat |
| U-1 | median waktu per catatan, proporsi lewat jalur cepat | `quickRecord.medianSaveMsByDomainVia` (`<domain>:<via>`), `quickRecord.quickShare` | `form_saved.meta.durationMs` (dari layar dibuka sampai tersimpan; jalur cepat dari kartu tampil sampai ketukan), `quick_repeat_used` |
| U-5 | pengguna melihat konteks ≥ 1×/hari | `feedbackAtSave.share` (hari-pengguna dengan `context_viewed` ÷ hari-pengguna aktif) | `usage_events` |
| U-6 | proporsi makan yang punya pasangan glukosa | `mealGlucosePairs.share` | `meal_logs` + `glucose_observations` (sebelum −90…+10 menit dan sesudah +60…+180 menit) |
| K-2 | ≥ 1 HbA1c tercatat per pengguna pilot | `clinicalAnchors.share` | `lab_results` |
| K-5 | target menyesuaikan dua arah | `adaptiveGoals.raisedWithConsent`, `adaptiveGoals.loweredWithConsent` | `audit_events` `goal_updated` dengan `source: weekly_reflection` dan `direction` |
| K-6 | rencana problem solving yang terlaksana | `problemSolving.plans`, `problemSolving.withConfirmedDay` | `coaching_actions` `PROBLEM_SOLVING` + `coaching_outcomes` |
| D-5 | laporan per 100 pengguna-minggu | `safetyReports.per100UserWeeks` | `incident_reports` |
| S-2 | waktu mematikan fitur < 1 menit | `operations.featureFlagChanges` (waktu efektif dijamin cache ≤ 30 dtk; diuji di `phase8.test.ts`) | `audit_events` `feature_flag_changed` |
| S-3 | ukuran tabel stabil | `operations.tableRows` | jumlah baris tabel yang dipangkas retensi |

### Fase 11

| Butir gap | Ukuran | Kunci keluaran | Sumber |
|---|---|---|---|
| K-4 | modul dibuka; rasio jawaban "di luar yang bisa kubantu" yang kini bertaut modul | `ecosystem.educationOpened`, `ecosystem.safetyRepliesWithModule` | `usage_events` `education_opened`; `conversation_messages` rute `SAFETY` dengan bagian `education` |
| K-7 | hit rate pencarian 20 kueri teratas | keluaran `scripts/food/search-hit-rate.ts` (`hits/total`, `curatedHits`) | pencarian referensi sungguhan di DB |
| K-8 | pengguna dengan pendamping aktif | `ecosystem.usersWithActiveCompanion` | `companion_links` |
| U-2 | pemakaian jalur suara | `ecosystem.voiceInputUses` | `usage_events` `voice_input_used` (sekali per sesi dikte) |
| U-4 | catatan pertama < 5 menit sejak akun dibuat; pemindahan dari mode coba | `ecosystem.firstRecordWithin5Min`, `ecosystem.guestMigrations` | `users.createdAt` + `record_created` pertama; `guest_records_migrated` |

Catatan U-2: tingkat koreksi draf setelah dikte belum diukur (perlu menandai draf yang berasal dari suara).

Ukuran yang belum bisa dihitung dari DB: SUS dan survei keterbacaan (U-5, U-7) butuh kuesioner pilot; laju pencapaian tujuan 60–80% (K-5) dihitung dari progres tujuan per minggu dan belum masuk skrip.
