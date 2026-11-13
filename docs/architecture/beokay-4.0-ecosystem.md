# beOkay 4.0 — Arsitektur ekosistem

Dokumen ini menjelaskan bagian yang ditambahkan di 4.0 dan alasan desainnya. Kode di `server/` sengaja tanpa komentar, jadi rasional ada di sini. Rencana dan audit awal: [`docs/reports/beokay-4.0-audit-and-plan.md`](../reports/beokay-4.0-audit-and-plan.md). Laporan hasil: [`docs/reports/beokay-4.0-report.md`](../reports/beokay-4.0-report.md).

## Alur

```
catatan manual / impor Health Connect / umpan balik
  → gerbang consent + mesin kualitas            features/consent, features/devices/quality.*
  → catatan domain (tabel yang ada)
  → outbox beramplop, transaksi yang sama        infrastructure/queue/{outbox,events}.ts, features/events/record-events.ts
  → proyeksi harian daily_behavior_facts         features/projections/daily-facts.*
  → konteks agen · coaching · JITAI · sosial     (semua membaca proyeksi)
  → skill terdaftar + FSM berbatas               features/agent/skills/*, agent.fsm.ts
  → persetujuan eksplisit (kuitansi operationId) agent.service.ts decide()
  → pengamatan hasil (dipicu peristiwa)          features/events/handlers.ts → outcomes.reconcile
  → memori (diusulkan, dikonfirmasi, berrevisi)  features/memory/memory.service.ts
  → keputusan intervensi berikutnya              interventions/intervention.policy.v3.ts
```

## 1. Kohort (`cohort-policy-v1`)

- Empat nilai: `PREVENTION`, `T2DM_SUPPORT`, `WELLNESS`, `UNDETERMINED`. Fungsi murni `determineJourney` di `features/cohort/cohort.policy.ts`.
- Hanya dari pernyataan pengguna: status diagnosis, tipe diabetes, `riskStatement` (`prediabetes_told`, `at_risk_told`, `none`, `undisclosed`), dan tahun lahir. Tidak ada kalkulator risiko dan tidak ada penetapan dari data (Q2).
- Diagnosis T2DM → `T2DM_SUPPORT`. Tipe 1/lain, di bawah 18 tahun, atau usia tidak diketahui → `UNDETERMINED` = pencatatan saja (Q3). Belum terdiagnosis + pernyataan risiko dari nakes → `PREVENTION`. Sisanya → `WELLNESS`.
- `riskStatement` ditolak (422) bila diagnosis diisi, agar jalur tidak ambigu.
- Kolom `health_profiles.journey/journey_source/journey_set_at/risk_statement`. Isi mundur: `eligible` lama → `T2DM_SUPPORT`, lainnya `UNDETERMINED`.
- Pengguna **tanpa** profil kesehatan dianggap `T2DM_SUPPORT` dengan `assumed: true` (`cohortService.resolve`). Ini kompatibilitas 3.0: onboarding mewajibkan profil kesehatan, jadi di aplikasi kasus ini tidak terjadi; hanya akun uji dan API langsung.
- Perubahan jalur menerbitkan `journey.changed`.
- Pemisahan konten: peta `MODULE_JOURNEYS` (edukasi) dan `STRATEGY_JOURNEYS` (strategi). Modul yang menyebut hipoglikemia, obat, glukometer, atau puasa dengan diabetes hanya untuk `T2DM_SUPPORT`/`UNDETERMINED`. Daftar edukasi, detail modul (404 bila jalur lain), edukasi keselamatan di percakapan, dan katalog strategi coaching difilter per jalur.

## 2. Peristiwa beramplop

- `outbox_events` mendapat kolom aditif `source, source_record_id, occurred_at, received_at, timezone, revision, consent_scope, quality, provenance, correlation_id, schema_version`. Outbox tetap satu-satunya angkutan; tidak ada layanan baru (T8).
- `emitRecordEvent(tx, …)` dipanggil **di dalam transaksi yang sama** dengan penulisan catatan: makan, glukosa, aktivitas (manual dan impor), asupan obat, check-in tujuan, vital, langkah, tidur. Kunci dedupe `record:<kind>:<id>:r<revision>:<action>` membuat ulangan idempoten.
- Peristiwa lain: `consent.granted/withdrawn`, `memory.changed`, `journey.changed`, `device.imported`, `challenge.joined/left/scored`.
- Registri penangan `features/events/handlers.ts`: satu tipe bisa punya beberapa pelanggan bernama; penangan lama `outcomes.handlers` didaftarkan ulang di sana. Pekerja dan job `outbox_drain` memakai `eventHandlers()`.
- Setelah impor perangkat, peristiwa milik pengguna itu dikuras lewat `background()` (`outbox.drainUser`, klaim dibatasi `user_id`). Ini untuk Vercel yang tidak punya pekerja latar (T4); sapuan terjadwal tetap jaring pengaman.

## 3. Proyeksi `daily-facts-v1`

- Satu baris per pengguna per tanggal lokal di `daily_behavior_facts`: menit aktif (manual/perangkat), jumlah dan sesi terpanjang, langkah (`NULL` bila tidak ada), menit tidur (`NULL` bila tidak ada), jumlah makan beserta kategorinya, cek glukosa (jumlah saja), konfirmasi obat, check-in, sumber.
- **Baca-tembus dengan tanda kotor.** `emitRecordEvent` menandai hari terdampak `dirty` di transaksi yang sama. `dailyFacts.ensure()` menghitung ulang hari yang hilang, kotor, berzona waktu lain, atau berversi lain sebelum dibaca. Penangan peristiwa memperbarui secara eager. Akibatnya pembaca tidak pernah melihat data basi walau outbox belum dikuras.
- Putar ulang = hapus baris lalu hitung ulang dari catatan; tes membuktikan hasilnya identik.
- Tidur dari beberapa perangkat yang tumpang tindih digabung sebagai irisan interval (`unionMinutes`), jadi jam tangan + ponsel tidak dihitung dua kali.
- Konsumen yang pindah di balik sakelar `projection_consumers` (bawaan nyala, bisa dimatikan untuk kembali ke kueri lama): hari aktif tantangan (`community.service.eligibleDays`), fakta coaching (`gatherFacts`: hari tercatat, sesi terpanjang, makan per hari), alat `get_daily_facts`, langkah berikutnya, `score-v2`. Tes paritas membandingkan kedua jalur pada fikstur yang sama.
- Tidak dipindah: `outcomes.reconcile` mencocokkan sesi tertentu dengan rencana tertentu (bukan agregasi), dan `explainWhy`. Keduanya tetap membaca catatan langsung.

## 4. Registri skill `skills-v1`

`features/agent/skills/registry.ts`. Delapan skill: `nutrition.coach`, `activity.planner`, `sleep.recovery`, `behavior.barrier_solver`, `prevention.education`, `health.trend_explainer`, `social.challenge_coach`, `memory.reflector`. Tiap skill memuat rute, intent, jalur yang diizinkan, consent wajib/opsional, alat baca yang boleh, tindakan yang butuh konfirmasi, daftar terlarang global, jalur bukti, akses memori, skema keluaran, tingkat keselamatan, anggaran (≤3 iterasi, ≤8 alat), dependensi, status, dan status tinjauan konten.

- `validateRegistry` menolak alat tak dikenal/terlarang, rute diklaim dua kali, skill untuk `UNDETERMINED`, anggaran di luar batas, dan skill tanpa consent dasar. Tes unit menjalankannya pada registri nyata.
- `selectSkills` → skill sah atau penolakan beralasan (`UNKNOWN_SKILL`, `SKILL_DISABLED`, `JOURNEY_NOT_ALLOWED`, `CONSENT_REQUIRED`), maksimum 2, diurutkan menurut `after`.
- Di percakapan (`conversation.skills.ts`), gerbang jalur ditegakkan untuk semua skill. Consent untuk enam skill lama tetap ditegakkan oleh implementasinya sendiri (balasan `consent_required` yang sama seperti 3.0); untuk tiga skill baru ditegakkan oleh gerbang. Setiap pemilihan dicatat (`skill_selection`).
- Multi-intent: kalimat dipecah pada kata sambung; maksimal satu skill tambahan dan hanya dari skill baru yang deskriptif (`SLEEP`, `SUPPORT`, `EDUCATION`). Bila salah satu klausa memicu keselamatan, pemecahan dibatalkan.
- Sakelar `skill_registry` mematikan semuanya dan mengembalikan perilaku 3.0.
- Model bahasa tidak diberi skill baru: prompt pengklasifikasi hanya dinetralkan dari "penyandang diabetes tipe 2". Rute `SLEEP` dan `EDUCATION` saat ini hanya dari aturan.

## 5. Mesin keadaan `agent-fsm-v1`

`features/agent/agent.fsm.ts`: 16 keadaan (`RECEIVED, SAFETY_SCREEN, ROUTE, SELECT_SKILL, PLAN, EXECUTE_READ_TOOLS, EVALUATE_EVIDENCE, DRAFT_RESPONSE, OUTPUT_GUARD, AWAIT_CONFIRMATION, EXECUTE_AUTHORIZED_ACTION, OBSERVE_OUTCOME, COMPLETED, BLOCKED, FAILED, CANCELLED`), tabel transisi, anggaran iterasi/alat/tenggat/ulang penjaga.

- `authorize(receipt)` hanya dari `AWAIT_CONFIRMATION` dan hanya dengan `operationId` + `ACCEPT`. Di `decide()`, transisi `EXECUTE_AUTHORIZED_ACTION → OBSERVE_OUTCOME → COMPLETED` ditulis sebagai `FSM_DECISION` dalam transaksi keputusan.
- Run agen 3.0 (gizi, aktivitas) tidak ditulis ulang. Saat status menetap, jalur keadaannya diturunkan (`pathFor`), diputar lewat mesin (gagal bila ilegal), lalu dicatat sebagai `FSM_PATH`; `agent_runs.fsm_state/skill_id/iterations` diisi.
- Skill baru berjalan di `skills/runner.ts` dengan loop berbatas: `PLAN → EXECUTE_READ_TOOLS → EVALUATE_EVIDENCE → (PLAN lagi bila bukti kurang dan anggaran sisa)`. Perencananya deterministik per skill. Setiap transisi dicatat sebagai peristiwa `FSM`.
- Perencana LLM (`react_llm_planner`) **tidak dibangun**; sakelarnya ada dan bawaan mati (`DEFAULT_OFF`). Membukanya butuh evaluasi bayangan yang dibaca pemilik (T7).

## 6. Tingkat alat

- 11 alat `READ_ONLY` di `agent.tools.ts`; empat baru: `get_daily_facts`, `get_device_quality`, `search_knowledge`, `get_memory_context`.
- `USER_CONFIRMED` (`plan_meal`, `plan_activity`, `save_food_preference`, `save_memory`, `join_challenge`, `adjust_goal`, `update_reminder`) terdaftar sebagai kontrak, tidak dapat dipanggil lewat `executeTool` (`REQUIRES_CONFIRMATION`), dan hanya terjadi lewat endpoint keputusan pengguna.
- `PROHIBITED` (`diagnose_condition`, `change_medication`, `set_insulin_dose`, `prescribe_exercise_volume`, `set_weight_target`, `interpret_lab_result`, `send_external_message`, `read_other_user`, `raw_query`, `write_health_record`) selalu ditolak (`PROHIBITED`).
- Bila konteks membawa `allowedTools` skill, alat di luar daftar ditolak (`SKILL_TOOL_NOT_ALLOWED`). Semua penolakan dicatat beserta `tier` dan `iteration`.
- Hasil alat diperlakukan sebagai data: potongan pengetahuan yang memuat pola injeksi atau klaim terlarang dibuang sebelum menyusun jawaban (`sanitize`), lalu dicatat di FSM.

## 7. Pengetahuan dan retrieval `retrieval-v1`

- Tabel publik `knowledge_documents` dan `knowledge_chunks` tidak punya `user_id` (diuji). Jalur A = 13 modul edukasi, jalur C = 14 strategi. Jalur B tetap `food_reference`; jalur D (catatan) dan E (memori) lewat alat terstruktur yang memfilter `user_id`.
- `knowledgeService.sync()` dijalankan job `education_sync`; status tinjauan mengikuti `education_modules`.
- Pipa: normalisasi → filter jalur, jalur pengguna, bahasa, status tinjauan, kedaluwarsa → leksikal (cakupan istilah, di memori karena korpus kecil) → vektor `mistral-embed` bila dikonfigurasi → RRF → satu potongan per dokumen → rerank mati → penilaian cakupan → jawab atau **abstain**.
- Produksi (`EDUCATION_INCLUDE_DRAFTS=false`) hanya menyajikan `REVIEWED`; karena belum ada yang ditinjau, produksi abstain (T2).
- Label kepastian `verified / reported / estimated / insufficient / unknown` dari `certaintyOf(provenans)`. Draf = `insufficient`.

## 8. Memori

- `memory_items` + `memory_type, source_ids, valid_from, last_verified_at, privacy_scope, conflict_state, superseded_by, paused_at, pause_reason`; tabel `memory_revisions` (PROPOSED, CONFIRMED, CORRECTED, PAUSED, RESUMED, DISMISSED, SUPERSEDED, CONFLICT). Revisi ikut terhapus bila ingatan dihapus.
- Kontradiksi: usulan berbeda untuk kunci yang sama ditandai `CONFLICTING` bersama ingatan aktifnya; konfirmasi menggantinya (revisi `SUPERSEDED`), penolakan membersihkan tanda.
- `retrieve(userId, skillId, budget)`: hanya ingatan aktif, tidak dijeda, tidak kedaluwarsa, sesuai jenis untuk skill itu, dibatasi anggaran; lingkup `SOCIAL` hanya dengan consent `social_outcomes_memory`. `activeFor` (dipakai coaching dan percakapan) kini juga melewati ingatan yang dijeda.
- Endpoint baru: `POST /api/me/memories/:id/pause|resume`, `GET /api/me/memories/:id/history`; `GET /api/me/memories` mengembalikan `items`, `paused`, `conflicts`.
- Pencabutan consent `personalized_ai` dalam transaksi yang sama: usulan ingatan ditolak, ingatan aktif dijeda (`CONSENT_WITHDRAWN`), rencana coaching usulan kedaluwarsa, rekomendasi terbuka dibatalkan. Tidak menunggu dibaca.
- Memori turunan dari proyeksi belum diusulkan otomatis; yang ada hanya baseline slot dalam mode bayangan (§10).

## 9. Perangkat: provenans dan kualitas `device-quality-v1`

- Skema impor menerima `dataOrigin` (nama paket asal di Health Connect), `recordingMethod`, dan `device` secara opsional; aplikasi lama tetap kompatibel. Disimpan di `daily_steps.data_origin`, `sleep_sessions.data_origin`, `activity_sessions.data_origin/recording_method/device_type`, dan di amplop peristiwa.
- Penilaian per sinyal per hari: `OK, PARTIAL (hari berjalan), NO_DATA, NOT_CONNECTED, STALE (>48 jam tanpa sinkron), CONFLICT (tumpang tindih lintas asal / sesi perlu ditinjau), IMPLAUSIBLE`. Flag: `LATE_SYNC, MULTIPLE_ORIGINS, OVERLAPPING_SESSIONS, NEEDS_REVIEW_SESSIONS, DAY_IN_PROGRESS, VALUE_OUT_OF_RANGE`.
- Tanpa data → `inference: UNKNOWN`. Tidak ada jalur kode yang mengubah ketiadaan data menjadi "tidak aktif".
- `GET /api/me/devices/status`: izin, sinkron terakhir, asal data, ringkasan 14 hari per sinyal, rincian harian, dan apakah data perangkat dipakai untuk saran (consent `device_data_coaching`).

## 10. Kecerdasan perilaku

- `behavior-features-v1` (`features/ml/behavior/behavior.model.ts`): fitur per pengguna-tanggal-slot hanya dari jendela **sebelum** tanggal label; hari tanpa data berlabel `null`.
- `baseline-v1`: laju historis per slot dengan pemulusan Beta(1,3). Didaftarkan di `model_versions` berstatus `SHADOW`; setiap evaluasi intervensi mencatat skor ke `ml_inference_runs` (mode `SHADOW`) di latar. Skor **tidak** memengaruhi keputusan.
- Harness evaluasi: pembagian per pengguna dan waktu, pemeriksaan kebocoran, Brier, PR-AUC, kalibrasi (ECE), fraksi data hilang, drift (PSI). `scripts/eval/behavior-eval.ts` menjalankannya pada fikstur sintetis **untuk membuktikan pipa benar**, bukan kinerja.
- Tidak ada model terlatih, bandit, atau uplift (T1).

## 11. JITAI `jitai-policy-v3`

- Fungsi murni `decideV3` membungkus v2; tanpa sinyal baru hasilnya identik dengan v2 (diuji), jadi jam tenang, batas harian/mingguan, jeda minimum, dan tidak-eskalasi tetap berlaku.
- Kelas: `INTERVENE, DEFER, ASK_FOR_CLARIFICATION, WITHHOLD, NO_INTERVENTION`. `WITHHOLD` untuk: balasan keselamatan dalam 24 jam (proaktif), ingatan `HEALTH_EVENT` aktif (proaktif), energi rendah yang dilaporkan, tujuan berbasis langkah dengan data langkah tidak andal, dan `REQUIRES_REVIEW`.
- Disimpan sebagai `NO_INTERVENTION` dengan alasan `WITHHOLD:<alasan>` dan `policy_version = jitai-policy-v3`, sehingga skema lama tetap valid. Tampilan memberi `decisionV3`.
- Check-in energi satu ketukan belum ada di aplikasi; masukan `energy` saat ini selalu `null`.
- Sakelar `jitai_v3`.

## 12. Sosial `score-v2` dan langkah berikutnya

- `score-v2` (`community/scoring.v2.ts`) dari proyeksi: hari aktif (sesi ≥10 menit atau check-in), bobot hari dengan bukti perangkat 1,0 dan manual 0,8, batas harian 1, bonus 0,5 bila hari aktif minggu ini melampaui rata-rata diri sendiri; hari istirahat tidak mengurangi. Tantangan berjalan tetap `score-v1`.
- Rekor pribadi (7 hari terbaik, beruntun terpanjang), kembali-setelah-jeda (≥7 hari), pita sebaya (0–1, 2–3, 4–5, 6–7 hari/minggu) dengan minimum 5 anggota; di bawah itu tanpa perbandingan. `GET /api/me/progress/peers` hanya memberi "separuh atas/bawah", tanpa nama dan nilai kesehatan.
- `GET /api/me/today/next-action`: satu langkah berikutnya dengan urutan prioritas: tindak lanjut keselamatan, jalur pencatatan saja, rekomendasi menunggu, rencana usulan, kembali-setelah-jeda, rencana diterima, usulan ingatan, refleksi akhir pekan, catat sesuatu. Beserta langkah alur `TODAY → NEXT_ACTION → CONFIRM → PROGRESS → REFLECTION → INSIGHTS → CHALLENGES`, keadaan Spark (`NEUTRAL, THINKING, ENCOURAGING, CELEBRATING, AWAITING_CONFIRMATION, SAFETY_WARNING`), dan progres `score-v2`.
- Peristiwa tantangan masuk outbox. Memakai hasil tantangan untuk memori masih dibatasi consent `social_outcomes_memory`; pengisian memori sosial otomatis belum dibangun.

## 13. Consent 1.1

Teks netral jalur; dua tujuan opsional baru `device_data_coaching` dan `social_outcomes_memory` (Q4: dipisah). Versi baru membuat persetujuan lama `reconsent_required` (mekanisme 3.0). Teks tetap draf hukum.

## 14. Sakelar dan rollback

| Sakelar | Bawaan | Efek bila mati |
|---|---|---|
| `projection_consumers` | nyala | komunitas dan coaching kembali ke kueri catatan lama |
| `skill_registry` | nyala | percakapan kembali ke dispatch 3.0 (tanpa gerbang jalur, tanpa rute tidur/edukasi, SUPPORT tanpa strategi) |
| `jitai_v3` | nyala | intervensi kembali ke `jitai-policy-v2` |
| `react_llm_planner` | **mati** | tidak ada implementasi; disiapkan untuk evaluasi bayangan |

Migrasi `p12_cohort_events` dan `p13_skills_knowledge_memory` punya skrip turun di `server/prisma/rollback/`. Keduanya diuji: turun, cek skema, lalu `db:migrate:deploy` lagi.
