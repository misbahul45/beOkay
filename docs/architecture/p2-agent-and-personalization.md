# Runtime agen, keselamatan, dan personalisasi (P2) — rancangan yang terpasang

## Alur (maksud `NUTRITION_ALTERNATIVES`)
```
POST /api/me/agent/runs {idempotencyKey, message, query?}
  consent (kesehatan + personalized_ai) → kunci idempoten → run CREATED
  → VALIDATING: saringan keselamatan permintaan (deterministik)  ── BLOCKED / NEEDS_CLINICAL_REVIEW → selesai, 0 alat
  → klasifikasi maksud + query (deterministik)                    ── UNSUPPORTED / perlu klarifikasi → COMPLETED, 0 alat
  → RUNNING: graf
       gather_context   : get_food_preferences, get_personalization
       retrieve         : search_food_reference (TKPI) ‖ search_user_foods
       validate+filter  : validateCandidate (sumber/angka) → kendala keras (alergi/pembatasan)
       rank             : kecocokan + kelengkapan data − penalti preferensi (aturan tetap)
  → rekomendasi OFFERED (maks 3) + run WAITING_FOR_USER           (tidak ada tulisan domain)
POST /api/me/agent/recommendations/:id/decision {operationId, decision, expectedVersion}
  consent → kuitansi (user, operationId) → status OFFERED & versi & belum kedaluwarsa
  → ACCEPT: periksa ulang kendala TERBARU → transaksi {status, kuitansi, planned_meals}
  → REJECT: transaksi {status, kuitansi, personalization_events + versi profil}
POST .../feedback {operationId, kind: CONSUMED|NOT_CONSUMED}  hanya untuk saran ACCEPTED; tidak membuat meal_logs
```
Run juga dapat dibaca (`GET /runs/:id`), dibatalkan (`POST /runs/:id/cancel`); `GET /api/me/planned-meals`, `GET|DELETE /api/me/personalization`, `GET /api/me/agent/tools`.

## Ketahanan dan idempotensi
- Seluruh state ada di PostgreSQL; keputusan tidak bergantung memori proses, jadi restart API tidak memengaruhi persetujuan.
- Efek samping hanya di keputusan pengguna dan satu transaksi. `planned_meals.recommendation_id` unik; `(user_id, operation_id)` unik pada kuitansi; pembaruan status memakai versi optimistik. Tiga permintaan bersamaan dengan operationId sama menghasilkan satu rencana (teruji).
- Run yang macet (proses mati di tengah) ditandai `FAILED` saat dibaca (>120 dtk); run yang kedaluwarsa menjadi `EXPIRED` beserta sarannya.
- Consent ditarik: `GET` run yang menunggu menjadi `BLOCKED/CONSENT_WITHDRAWN`, saran `INVALIDATED` dan disembunyikan; keputusan dan run baru ditolak 403.

## Keselamatan (di luar model)
`agent.safety.ts` (`safety-policy-v1`, kini `safety-policy-v2` — lihat [system-overview §6.8](system-overview.md)): saringan permintaan (obat/dosis, diagnosis, klaim kesembuhan/penurunan gula, pembatasan ekstrem, gejala mendesak), validasi kandidat (sumber wajib, angka dalam rentang, nilai kosong tetap kosong), dan gerbang klaim terlarang untuk setiap teks penjelasan. Penjelasan dibuat dari **templat**, bukan model. Tidak ada LLM dalam alur ini; karena itu injeksi prompt lewat dokumen yang diambil tidak punya jalur untuk memengaruhi alat atau keputusan.

## Personalisasi (bukan pembelajaran mesin)
Penolakan menambah bobot (maks 5) pada kata nama makanan yang ditolak (di luar kata pencarian). Penalti = bobot × 0,6 dikurangkan dari skor. Setiap perubahan menaikkan versi profil dan menulis `personalization_events` (alasan, saran sumber, perubahan). Pengguna dapat melihat dan **menghapus** hasilnya; versi tetap naik agar dapat diaudit. Tidak ada pembaruan model produksi dari umpan balik.

## Pembaruan 10 November 2026
- **Giliran lanjutan:** `agent_runs.parent_run_id`/`turn`. "pilihan lain" = ulang maksud+kueri induk dengan `excludeKeys` (semua kunci kandidat yang sudah ditawarkan sepanjang rantai); "kenapa" = penjelasan dari `rankingReason` tanpa alat. Induk harus milik pengguna yang sama.
- **Teks LLM (opsional, consent `ai_text_generation`):** setelah peringkat selesai dan SEBELUM saran disimpan, `polish()` meminta Mistral menulis ulang penjelasan templat. Gerbang keluaran (`gateLlmText`): tidak kosong, ≤ 420 karakter, tanpa tautan/markup, lolos `FORBIDDEN_CLAIMS`, memuat nama persis, tanpa angka di luar fakta. Gagal apa pun → templat; `recommendations.payload.textSource` dan peristiwa `LLM_TEXT` mencatat hasilnya. LLM tidak memilih atau meranking.
- **Streaming:** `?async=1` → 202 dan `execute()` berjalan di latar; `GET /runs/:id/stream` (SSE) memutar ulang `agent_run_events` lalu mengikuti, dengan `Last-Event-ID`, detak jantung, dan peristiwa `state` penutup. Sumber kebenaran tetap tabel peristiwa (aliran putus tidak kehilangan apa pun).
- **Outbox:** `outbox_events` ditulis dalam transaksi keputusan/umpan balik/hasil. Pekerja dalam proses mengklaim dengan `FOR UPDATE SKIP LOCKED`, backoff eksponensial, dead-letter setelah 5. Penangan: `outcome.observed|retracted` menerapkan personalisasi; `recommendation.decided|feedback` mencatat.
- **Hasil terukur:** `outcomes.reconcile(userId)` (saat daftar rencana dibaca + sapuan 60 dtk) mencocokkan rencana diterima dengan butir catatan makan / sesi aktivitas nyata → `recommendation_outcomes` (unik per rekomendasi) + `outcome.observed`. Bukti diarsipkan → hasil dihapus + `outcome.retracted`. Hanya untuk pengguna yang masih memberi `health_data_processing` dan `personalized_ai`.
- **Model:** status `APPROVED` mewajibkan `approved_at` + `approval_note` (CHECK). `dishService.assist()` = satu pintu foto: non-APPROVED → bayangan; APPROVED → LIVE dengan ambang 0,85 dan fallback senyap. `warmup()` memanaskan Modal tanpa data pengguna.
- **Pemulihan:** `GET /api/me/agent/pending` mengembalikan run `WAITING_FOR_USER` yang belum kedaluwarsa (maks 5).

## Batas dan yang belum ada
(Catatan: butir ini ditulis pada tahap awal. Kini ada maksud aktivitas, giliran lanjutan, SSE, outbox, teks LLM opsional, ML bayangan/live, komunitas, dan UI Flutter; lihat pembaruan di atas.) Yang masih belum ada: alat konteks glukosa/ringkasan/kalkulator/bukti terkurasi, metrik observabilitas agregat, tinjauan klinisi atas kebijakan keselamatan.
