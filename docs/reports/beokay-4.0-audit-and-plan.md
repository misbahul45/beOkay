# beOkay 4.0 — Audit, Goal, dan Rencana

> Disusun 13 November 2026 dari pohon kerja `main` @ `1305f83`. Dokumen ini **tidak mengubah kode**. Isinya: (1) audit terhadap kode sumber, bukan terhadap laporan lama; (2) kontrak goal 4.0; (3) rencana P0–P5. Belum ada yang dikerjakan; menunggu keputusan pemilik di §8.
>
> Status: `DRAFT — menunggu persetujuan pemilik`.

## 0. Ringkasan

1. **Baseline hijau dan terverifikasi hari ini**: backend 406/406 tes (73 berkas), `tsc --noEmit` bersih, Flutter 237/237 tes, `flutter analyze` tanpa temuan.
2. **Fondasi keselamatan sudah kuat dan harus dipertahankan**: saringan keselamatan deterministik sebelum model, registri alat deny-by-default dengan anggaran 8 panggilan, saran ≠ catatan, persetujuan tepat-sekali (`operationId`), consent per tujuan, outbox transaksional, memori yang selalu diusulkan dulu.
3. **Lima gap struktural yang menentukan 4.0** (semuanya terbukti di kode, §2):
   - **Satu kohort saja.** Seluruh sistem mengandaikan T2DM dewasa. Tidak ada jalur pencegahan/prediabetes atau gaya hidup umum; prompt pengklasifikasi pun menulis "penyandang diabetes tipe 2".
   - **Outbox belum menjadi tulang punggung.** Hanya keputusan agen/coaching/intervensi yang masuk outbox, dan 6 dari 8 penangannya kosong. Catatan domain (makan, glukosa, aktivitas, impor perangkat) tidak menerbitkan peristiwa. "Hari aktif" dihitung terpisah di sedikitnya 5 modul.
   - **Tidak ada registri skill.** Rute adalah union TypeScript tetap; alat diikat ke `allowedIntents`. Tidak ada kohort, kelas risiko, bukti wajib, atau metrik evaluasi per skill.
   - **RAG hanya satu jalur** (`food_reference`). Edukasi dipetakan statis dari kode keselamatan, bukan diambil; katalog strategi adalah konstanta; tidak ada tabel dokumen pengetahuan bermetadata.
   - **Data perangkat tanpa provenans dan tanpa mesin kualitas.** Lima jenis Health Connect diimpor, tetapi aplikasi sumber/perangkat tidak dikirim, tidak ada deteksi tumpang tindih, tidak ada status kesegaran/cakupan, dan belum pernah diuji dengan jam tangan nyata.
4. **Empat hal tidak bisa saya selesaikan sendiri** dan akan tetap berlabel jujur: tinjauan klinisi atas konten (edukasi, strategi, pesan keselamatan, konten prediabetes baru), pengujian jam tangan nyata, pelatihan model perilaku (belum ada data pengguna nyata dan belum ada izin etik), dan tinjauan hukum teks consent.
5. **Level bukti yang realistis di akhir 4.0: Level 1** (fungsi teknis terbukti). Level 2 butuh sesi pengguna nyata; Level 3–4 butuh pilot dan studi klinis.

## 1. Metode dan baseline

| Yang dilakukan | Hasil |
|---|---|
| Membaca kode: `server/src/features/{agent,conversation,memory,episodes,interventions,coaching,community,devices,ml,education,food-reference,health-profile,consent,jobs,today}`, `infrastructure/queue/outbox.ts`, `routes.ts`, `prisma/schema.prisma`, serta `app/lib/features/devices`, `app/lib/core/widgets/beokay_{spark,avatar}.dart` | dasar §2 |
| `docker compose -f compose.test.yaml run --rm tester bun test` (DB uji terisolasi) | **406 lulus, 0 gagal**, 3.940 expect, 73 berkas, 27 dtk |
| `bun run typecheck` di container uji | exit 0 |
| `flutter test` (host) | **237 lulus** |
| `flutter analyze` (host) | tanpa temuan |
| Inventaris | server 321 berkas TS / 19.073 baris (tanpa generated), 46 modul fitur, 82 model Prisma, 31 migrasi; aplikasi 235 berkas Dart / 40.242 baris, 38 berkas tes |

**Tidak diverifikasi dalam audit ini** (jadi berlabel `UNVERIFIED` di bawah): koleksi Bruno (tidak dijalankan), CI GitHub Actions, kesehatan produksi Vercel/Neon, endpoint Modal, E2E emulator, perangkat fisik, TalkBack.

Catatan: laporan lama menyebut 402 tes backend; angka hari ini 406. Dokumentasi tidak dipakai sebagai bukti.

## 2. Audit: status nyata

Label: `TESTED` (ada kode dan tes otomatis lulus hari ini), `BUILT` (ada kode, tes tidak mencakup atau tidak saya jalankan), `PARTIAL`, `UNVERIFIED`, `NOT_IMPLEMENTED`, `EXTERNALLY_BLOCKED`, `REQUIRES_CLINICAL_REVIEW`.

### 2.1 Kapabilitas baseline (brief §1)

| Kapabilitas | Status | Bukti / catatan |
|---|---|---|
| Flutter Android, Riverpod 3.5, go_router 18 | TESTED | `app/pubspec.yaml`; 237 tes |
| API Bun/TypeScript | TESTED | `server/src/routes.ts`, 46 modul |
| Prisma 7 + PostgreSQL + pgvector | TESTED | 82 model; pencarian vektor di `food-reference/reference.service.ts` |
| Better Auth + consent per tujuan | TESTED | 11 tujuan di `consent/consent.policy.ts`; teks consent masih draf → tinjauan hukum `EXTERNALLY_BLOCKED` |
| Gizi, glukosa, aktivitas, obat, tujuan | TESTED | tes integrasi per domain |
| Health Connect | PARTIAL | 5 jenis (latihan, langkah, berat, glukosa, tidur) dengan izin per jenis; **tanpa provenans aplikasi/perangkat, tanpa mesin kualitas**; perangkat nyata `UNVERIFIED` |
| Sinkron offline | TESTED | `sync.service.ts`, `offline_sync_test.dart` |
| Komunitas, tantangan, papan peringkat, pengakuan | TESTED | `score-v1`, kohort minimum 5, alias, moderasi |
| JITAI + coaching lingkar tertutup | TESTED | `jitai-policy-v2` (fungsi murni), `coach-rules-v2` |
| Outbox transaksional | PARTIAL | mekanisme benar (SKIP LOCKED, backoff, dead-letter, `dedupeKey`), **cakupan sempit**: lihat 2.3 |
| SSE dan WebSocket | BUILT | ada tes realtime; di Vercel bergantung Upstash (`UNVERIFIED` hari ini) |
| Memori disetujui + episode mingguan | TESTED | `memory.service.ts`, `episodes.model.ts` |
| Graf agen deterministik + anggaran alat | TESTED | `agent.graph.ts`, `agent.tools.ts` (`MAX_TOOL_CALLS = 8`) |
| Pengklasifikasi LLM + judge hanya-menahan | TESTED | `intent-classifier.ts`; korpus injeksi 100 kalimat |
| Retrieval gizi + penemuan via web | TESTED | hibrida leksikal + vektor + RRF; web hanya ke parser deterministik |
| Registri model + Modal | BUILT | `model-registry.ts`; endpoint Modal `UNVERIFIED` hari ini; model hidangan dinilai tidak relevan untuk Indonesia oleh audit sebelumnya |
| Bruno | PARTIAL | 104 permintaan, **hanya folder 08–19 (era P0/P1)**. Tidak ada permintaan untuk auth/consent, agen, percakapan, coaching, komunitas, perangkat, memori, intervensi |
| Tes backend dan Flutter | TESTED | angka di §1 |

### 2.2 Kohort dan posisi produk (brief §2)

| Temuan | Status | Bukti |
|---|---|---|
| Hanya satu kelayakan: `diagnosed` + `type_2` + dewasa → `eligible`; sisanya `needs_review`/`unknown` | NOT_IMPLEMENTED (tiga jalur) | `health-profile/eligibility.ts` |
| `diagnosisStatus` tidak punya nilai prediabetes/berisiko | NOT_IMPLEMENTED | `health-profile.schema.ts` |
| Prompt pengklasifikasi mengandaikan T2DM | perlu diubah | `intent-classifier.ts` (`CLASSIFIER_SYSTEM`) |
| 10 modul edukasi seluruhnya topik T2DM, status draf | REQUIRES_CLINICAL_REVIEW | `content/education/modules.ts`; produksi menyembunyikan draf |
| Batas keselamatan (tanpa diagnosis, tanpa dosis, tanpa eskalasi latihan) | TESTED | `safety-policy-v2`, 10 aturan, korpus 99 kalimat; belum ditinjau klinisi |
| `AGENTS.md` masih menyatakan "T2DM, adult, personal" dan cakupan "jangan melebar" | usang | perlu diperbarui bila 4.0 disetujui |

### 2.3 Ekosistem berbasis peristiwa (brief §3)

| Temuan | Status | Bukti |
|---|---|---|
| Penerbit outbox hanya 8 jenis: `recommendation.decided/feedback`, `outcome.observed/retracted`, `intervention.responded`, `coaching.decided/feedback/checkin` | PARTIAL | `grep outbox.enqueue` → 8 titik |
| 6 dari 8 penangan adalah fungsi kosong | PARTIAL | `agent/outcomes.ts` `handlers` |
| Catatan domain dan impor perangkat **tidak** menerbitkan peristiwa | NOT_IMPLEMENTED | `device-import.service.ts`, layanan domain |
| Amplop peristiwa: hanya `id, userId, type, payload, dedupeKey`. Tidak ada `source, sourceRecordId, occurredAt, receivedAt, timezone, revision, consentScope, quality, provenance, correlationId` | NOT_IMPLEMENTED | model `OutboxEvent` |
| "Hari aktif/aktivitas terlaksana" dihitung sendiri-sendiri: `community.service.ts` (≥ 10 menit), `coaching.service.ts` (`matchesActivity`), `agent/outcomes.ts` (≥ 50% durasi), `agent.tools.ts` (28 hari), `activityService.daily`, statistik | duplikasi | bertentangan dengan "satu aliran hasil" |
| Rekonsiliasi hasil berjalan lewat sapuan berkala dan saat dibaca, bukan dipicu peristiwa | PARTIAL | `sweepOutcomes`, `coachingService.reconcile` |
| Duplikat, koreksi, arsip, hasil ditarik | TESTED | kunci unik `(userId, source, externalId)`, `record_revisions`, `outcome.retracted` |
| Pencabutan consent | PARTIAL | dibatalkan **malas** saat dibaca (`runView`, `listOpen`); tidak ada invalidasi berantai yang dipicu peristiwa |
| Data hilang = tidak diketahui | TESTED | langkah `null`, `DayState` punya `UNKNOWN`, "hari tanpa baris = belum terlihat" |
| Putar ulang peristiwa | NOT_IMPLEMENTED | tidak ada proyeksi yang dapat dibangun ulang dari peristiwa |

### 2.4 Registri skill dan ReAct terbatas (brief §4–5)

| Temuan | Status | Bukti |
|---|---|---|
| Registri skill berversi dengan kohort, consent, kelas risiko, bukti wajib, skema I/O, metrik | NOT_IMPLEMENTED | rute = union `Route` di `conversation.router.ts` |
| Padanan fungsional 6 dari 8 skill sudah ada sebagai kode: gizi (`runNutritionGraph`), aktivitas (`runActivityGraph`), hambatan (`coaching.strategies.ts`), tren (`statsReply`), tantangan (`communityReply`), refleksi (`reflectionReply` + episode) | PARTIAL | perlu dibungkus, bukan ditulis ulang |
| `sleep.recovery`, `prevention.education` | NOT_IMPLEMENTED | tidur hanya ringkasan durasi; tidak ada konten pencegahan |
| Gerbang keselamatan → consent → router deterministik → klasifikasi LLM terbatas → validasi | TESTED | urutan di `routeMessage` + `createLlmRouter` |
| LLM tidak bisa menyebut alat atau melebarkan izin | TESTED | skema Zod `.strict()`, daftar rute tertutup |
| Komposisi multi-intent dengan urutan dependensi | NOT_IMPLEMENTED | satu pesan → satu rute |
| Mesin keadaan eksplisit | PARTIAL | status run: `CREATED, VALIDATING, RUNNING, WAITING_FOR_USER, COMPLETED, BLOCKED, FAILED, EXPIRED, CANCELLED`; belum ada `RETRIEVE_EVIDENCE, EVALUATE, OBSERVE, REFLECT, CLARIFY` sebagai keadaan dan belum ada tabel transisi yang ditegakkan |
| Iterasi penalaran (maks 3) | NOT_IMPLEMENTED | graf berjalan lurus sekali |
| Anggaran alat, batas waktu per alat, batas ukuran hasil, audit setiap penolakan | TESTED | `executeTool` |
| Anggaran token/penyedia, batas ulang, jalur kompensasi | PARTIAL | `max_tokens` 160, batas waktu 6 dtk, batas laju; tidak ada anggaran per run atau kompensasi |
| Tingkat izin alat `READ_ONLY / USER_CONFIRMED / PROHIBITED` | PARTIAL | semua 7 alat bersifat baca; penulisan terjadi di `decide()` di luar registri; tidak ada atribut tingkat |
| Peristiwa eksekusi terstruktur + ID bukti; tanpa chain-of-thought | TESTED | `agent_run_events`, `agent_tool_calls` (hash argumen), `evidenceRefs` |
| Uji injeksi lewat **respons alat** | PARTIAL | parser web/label diuji; belum ada uji respons alat beracun lintas alat (nama makanan, isi memori, potongan pengetahuan) |

### 2.5 RAG multi-jalur (brief §6)

| Jalur | Status | Catatan |
|---|---|---|
| A. Edukasi klinis/pencegahan tertinjau | NOT_IMPLEMENTED sebagai retrieval; konten `REQUIRES_CLINICAL_REVIEW` | modul ada sebagai teks utuh, dipilih lewat peta statis `SAFETY_MODULES` |
| B. Pangan Indonesia terverifikasi | TESTED | referensi TKPI (`verified_auto` = konsisten internal, bukan diperiksa manusia; jumlah baris di DB dev tidak dihitung ulang hari ini) + 45 hidangan kurasi di `content/food/curated-dishes.ts` (menunggu tinjauan ahli gizi); ambang kemiripan 0,75 adalah heuristik 14 kueri menurut komentar kode |
| C. Katalog strategi perubahan perilaku | PARTIAL | 14 strategi sebagai konstanta, `DRAFT_NOT_CLINICALLY_REVIEWED`; tidak diambil lewat retrieval |
| D. Fakta kesehatan pribadi | PARTIAL | lewat kueri terstruktur berbatas `user_id` (statistik); bukan jalur retrieval berlabel |
| E. Memori dan hasil sebelumnya | PARTIAL | `memoryService.activeFor`, `episodesService.avoidSlots` |
| Metadata dokumen (`source, sourceDate, lastReviewedAt, reviewer, contentHash, version, cohort, language, publicationStatus, evidenceType, expiration`) | PARTIAL | `education_modules` punya versi, hash, status, peninjau; tidak punya kohort, bahasa, jenis bukti, kedaluwarsa |
| Penilaian cakupan bukti dan abstain | PARTIAL | `coverage`, `completeness`, "data kurang" ada di graf gizi/aktivitas; belum ada penilaian lintas jalur |
| Label `verified / reported / estimated / insufficient / unknown` | PARTIAL | ada `provenance` dan `completeness`, kosakata belum seragam |
| Pemisahan data pribadi dan pengetahuan publik | TESTED secara struktur | tabel terpisah; tidak ada chunk campuran |

### 2.6 Memori lintas sesi (brief §7)

| Temuan | Status | Bukti |
|---|---|---|
| Usul → konfirmasi → aktif; tolak; ubah dengan versi; hapus satu/semua; matikan; ekspor | TESTED | `memory.service.ts`, `export.service.ts` |
| Ekstraksi mengutamakan pernyataan eksplisit; usulan model wajib berdasar teks; kata sensitif ditolak | TESTED | `memory.extract.ts`, `validateProposal` |
| Kedaluwarsa per jenis (kondisi sementara 7–30 hari, hambatan 60, konteks makan 180) | TESTED | `ttlDaysFor` |
| Tipe memori (kerja/semantik/episodik/turunan/prosedural) | PARTIAL | satu `category = "PREFERENCE"`; episodik ada di tabel lain; **memori perilaku turunan dari peristiwa nyata tidak ada** |
| Kolom `sourceIds[]`, `validFrom`, `lastVerifiedAt`, `privacyScope`, `conflictState`, riwayat koreksi | NOT_IMPLEMENTED | model `MemoryItem` hanya punya `sourceId` tunggal, `confidence`, `version` |
| Deteksi kontradiksi (mis. suka dan tidak suka aktivitas yang sama) | NOT_IMPLEMENTED | |
| Penjelasan memori mana yang dipakai sebuah saran | PARTIAL | ada untuk rencana aktivitas; tidak seragam |
| Jeda per butir; invalidasi berantai saat consent dicabut | NOT_IMPLEMENTED | saat ini hanya sakelar global dan pemeriksaan saat dibaca |
| Umpan balik hasil mengubah strategi hanya bila andal | PARTIAL | personalisasi makanan memakai hasil terukur; strategi/slot memakai hitungan tolakan; tidak ada ambang keandalan eksplisit |

### 2.7 ML perilaku (brief §8)

| Temuan | Status |
|---|---|
| Aturan klinis tidak digantikan ML | TESTED (tidak ada ML di jalur keputusan) |
| Registri model sebagai sumber persetujuan dan provenans | TESTED |
| Mode bayangan | PARTIAL (ada untuk pengenal hidangan lewat `ml_inference_runs`) |
| Fitur perilaku, baseline deterministik untuk waktu/propensitas/kecocokan strategi | NOT_IMPLEMENTED |
| Model perilaku terlatih | NOT_IMPLEMENTED dan `EXTERNALLY_BLOCKED`: tidak ada data pengguna nyata, tidak ada izin etik |

### 2.8 JITAI dan coaching (brief §9)

| Temuan | Status | Bukti |
|---|---|---|
| Jam tenang, batas harian/mingguan, jeda minimum, penekanan ulang, tunda | TESTED | `intervention.policy.ts` |
| Kelas keputusan | PARTIAL | ada `INTERVENE, DO_NOT_INTERVENE, DEFER, ASK_FOR_CLARIFICATION, REQUIRES_REVIEW`; brief meminta `WITHHOLD` dan `NO_INTERVENTION` dibedakan |
| Masukan: peristiwa terbaru yang andal, energi/lelah | NOT_IMPLEMENTED | konteks hanya dari log keputusan sendiri; tidak membaca data perangkat atau kualitasnya |
| Pengiriman dicatat terpisah dari penerimaan | TESTED | `deliveryStatus` vs `response` |
| Setelah rencana disetujui: pengingat opsional, amati, konfirmasi manual, umpan balik, episode mingguan | TESTED | `coaching.service.ts`, `episodes.service.ts` |
| Kosakata hasil | PARTIAL | ada `PLANNED, OBSERVED, USER_CONFIRMED, NOT_OBSERVED, RETRACTED, UNKNOWN`; perlu dipetakan ke `ACCEPTED, REJECTED, SELF_REPORTED, …` tanpa mengganti nilai tersimpan |

### 2.9 Jam tangan dan perangkat (brief §10)

| Temuan | Status | Bukti |
|---|---|---|
| Langkah, tidur, berat, glukosa, latihan dari Health Connect; izin dan preferensi per jenis (semua mati bawaan) | TESTED di tingkat API dan widget | `device-import.*`, `health_signals.dart`, `device_import_test.dart` |
| Idempotensi dan duplikat | TESTED | kunci unik per `(userId, source, externalId)` |
| Provenans aplikasi sumber/perangkat/metode perekaman | NOT_IMPLEMENTED | `source` selalu `"health_connect"`; klien tidak mengirim `dataOrigin` |
| Kesegaran sinkron | PARTIAL | `syncedAt` hanya di langkah; tidak ada status koneksi/izin di server |
| Deteksi tumpang tindih (dua aplikasi menulis langkah yang sama; sesi jam tangan bertumpuk dengan catatan manual) | NOT_IMPLEMENTED | |
| Mesin kualitas data perangkat | NOT_IMPLEMENTED | |
| Rantai jam tangan → Health Connect → Flutter → API → catatan → proyeksi pada perangkat nyata | UNVERIFIED / EXTERNALLY_BLOCKED | hanya izin dan baca di emulator tanpa data latihan |
| Pendamping Wear OS | NOT_IMPLEMENTED | opsional di brief; lihat §8 Q6 |

### 2.10 Motivasi sosial (brief §11)

| Temuan | Status |
|---|---|
| Opt-in, alias anonim, kohort minimum, moderasi/lapor, tanpa nilai kesehatan di skor, hari istirahat tidak mengurangi skor, batas isi mundur 2 hari | TESTED |
| Tantangan rekor pribadi, kelompok sebaya sepadan, misi konsistensi tim, pengakuan kembali-setelah-jeda, rekomendasi tantangan | NOT_IMPLEMENTED |
| Anti-curang selain batas mundur (bobot catatan manual vs perangkat, batas harian eksplisit) | PARTIAL |
| Hasil sosial masuk ke lingkar coaching dan memori | NOT_IMPLEMENTED |

### 2.11 Spark dan pengalaman (brief §12)

| Temuan | Status |
|---|---|
| Identitas Spark, 10 keadaan (`idle, listening, thinking, searching, responding, encouraging, celebrating, neutral, error, paused`) | TESTED (`beokay_spark_test.dart`) |
| `AWAITING_CONFIRMATION`, `SAFETY_WARNING` | NOT_IMPLEMENTED |
| Kurangi gerak (preferensi + sistem), tema gelap, uji teks 2× | TESTED sebagian (`large_text_regressions_test.dart`, `palette_contrast_test.dart`) |
| Alur `TODAY → NEXT ACTION → CONFIRM → PROGRESS → REFLECTION → INSIGHTS → CHALLENGES` | PARTIAL: `today.service.ts` hanya menggabungkan ringkasan harian; "langkah berikutnya" tersebar di kartu intervensi, coaching, dan asisten |
| TalkBack, perangkat kelas rendah | UNVERIFIED |
| Arah visual "editorial sports, netral dingin" | NOT_IMPLEMENTED; palet sekarang hangat (`AppColors.cream`); wajib lewat FigCraft dulu |

### 2.12 Privasi, keamanan, evaluasi (brief §13–14)

| Temuan | Status |
|---|---|
| Kepemilikan sesi, consent, idempotensi, revisi, ekspor, hapus, audit, eskalasi keselamatan | TESTED |
| Sapuan IDOR/401 berbasis tabel rute | TESTED |
| Injeksi prompt (100 kalimat), tanpa-consent = 0 panggilan model | TESTED |
| Kebocoran memori lintas pengguna, penulisan memori tanpa izin, data perangkat basi, notifikasi ganda, keputusan serentak, privasi komunitas | PARTIAL (tersebar; belum ada suite adversarial tunggal) |
| Cadangan dan pemulihan | BUILT (skrip ada), uji pulih `UNVERIFIED` |
| Analitik pemakaian ber-consent | TESTED (`usage` modul) |
| Metrik brief §14 (retensi H7/H28, waktu ke aksi pertama, laju koreksi memori, cakupan sinkron, laju jawaban berdasar bukti) | PARTIAL: peristiwa mentah ada, perhitungannya belum |

## 3. Ketegangan antara brief dan keadaan repo

| # | Ketegangan | Sikap dalam rencana |
|---|---|---|
| T1 | Brief meminta model perilaku; tidak ada data nyata dan tidak ada izin etik | Bangun fitur, baseline deterministik, mode bayangan, dan harness evaluasi. **Tidak melatih model** dari data pengguna. Label `EXTERNALLY_BLOCKED` |
| T2 | Brief meminta sumber medis tertinjau sebelum produksi; semua konten masih draf | Jalur A dan C dibangun dan diuji dengan draf di lingkungan uji; produksi tetap hanya menyajikan `REVIEWED`. Bila tidak ada yang tertinjau, jawaban = abstain + rujukan |
| T3 | Brief meminta uji jam tangan nyata | Saya bisa menggerakkan ponsel lewat adb; jam tangan harus dari pemilik. Tanpa itu label tetap `UNVERIFIED` |
| T4 | Vercel tidak menjalankan pekerja latar; outbox dikuras tiap ~5 menit | Setelah impor perangkat, kuras peristiwa milik pengguna itu lewat `background()`; sapuan terjadwal tetap jadi jaring pengaman |
| T5 | Arah visual baru vs aturan "FigCraft dulu"; MCP `figcraft` gagal tersambung di sesi ini (`CONNECTION_CLOSED`) | Halaman desain dibuat lewat `figcraft-cli` tanpa antarmuka seperti Fase 8–11; bila itu juga gagal, UI berhenti dan dilaporkan |
| T6 | Tiga kohort mengubah teks consent dan posisi produk; `AGENTS.md` usang | Versi kebijakan consent baru memicu `reconsent_required` (mekanisme sudah ada). `AGENTS.md` diperbarui di P1 |
| T7 | "ReAct" bisa dibaca sebagai agen bebas | Ditolak. Perencana bawaan deterministik; usulan langkah dari LLM berada di balik sakelar, mulai dari mode bayangan |
| T8 | "Jangan menambah layanan tanpa kebutuhan terukur" | Tidak ada layanan baru. Semua di Postgres/pgvector dan proses API yang ada |

## 4. Goal 4.0

```yaml
goal_id: beokay-4.0
version: 1
status: DRAFT
title: Ekosistem kesehatan preventif yang terikat klinis, berdasar bukti, dan adaptif
```

**Outcome.** Di repositori beOkay, satu pengguna dewasa dari salah satu dari tiga jalur (pencegahan, dukungan T2DM, gaya hidup umum) dapat meminta dukungan gaya hidup dan menerima rencana mikro yang (a) dipilih oleh skill terdaftar yang sah untuk jalurnya, (b) disertai bukti yang dapat ditelusuri dan label kepastiannya, (c) hanya berlaku setelah persetujuan eksplisit, (d) direkonsiliasi dengan catatan atau data perangkat lewat satu aliran peristiwa, dan (e) mengubah saran berikutnya lewat memori yang bisa dilihat, dikoreksi, dan dihapus pengguna. Semua batas keselamatan 3.0 tetap berlaku.

**Target.** Repositori `beOkay` (`server/`, `app/`, `docs/`), lingkungan uji Docker terisolasi dan emulator/ponsel Android. Produksi (Vercel/Neon) **bukan** target goal ini; deploy adalah keputusan terpisah.

**Kriteria keberhasilan** (semua memblokir kecuali ditandai):

| ID | Kriteria | Validator |
|---|---|---|
| C1 | Tidak ada regresi: 406 tes backend dan 237 tes Flutter yang ada tetap lulus; typecheck dan analyze bersih | `bun test`, `bun run typecheck`, `flutter test`, `flutter analyze` |
| C2 | Tiga jalur punya kelayakan dan pemisahan konten yang ditegakkan: skill, edukasi, dan teks untuk jalur lain tidak pernah muncul | tes matriks kohort × skill × konten (0 kebocoran) |
| C3 | Setiap catatan domain dan impor perangkat menerbitkan tepat satu peristiwa beramplop lengkap dalam transaksi yang sama; duplikat, sinkron terlambat, koreksi, arsip, dan putar ulang menghasilkan proyeksi yang sama | tes integrasi idempotensi dan putar ulang (proyeksi dibangun ulang = identik) |
| C4 | "Hari aktif" dan hasil rencana dihitung di satu tempat; komunitas, coaching, hasil agen, dan JITAI membaca proyeksi yang sama | tes paritas terhadap perhitungan lama pada fikstur yang sama; pencarian kode: tidak ada kueri agregasi aktivitas di luar modul proyeksi untuk keempat konsumen itu |
| C5 | Registri skill memuat 8 skill dengan seluruh atribut wajib; pemilihan skill di luar registri, kohort, atau consent ditolak dan dicatat | tes kebijakan + tes skema registri |
| C6 | Setiap run agen mengikuti tabel transisi; maksimum 3 iterasi dan 8 panggilan alat ditegakkan; alat `USER_CONFIRMED` tidak pernah berjalan tanpa kuitansi persetujuan | tes properti mesin keadaan; tes anggaran; tes negatif |
| C7 | Suite adversarial lulus dengan 0 pelanggaran: injeksi lewat pesan, lewat respons alat, kebocoran memori lintas pengguna, IDOR, penulisan memori tanpa izin, pencabutan consent | `tests/adversarial/*` |
| C8 | Retrieval tiap jalur terisolasi (tidak ada baris pribadi di hasil jalur publik dan sebaliknya); jawaban faktual membawa salah satu dari 5 label kepastian atau abstain | tes isolasi jalur; evaluasi retrieval pada set kueri berlabel (dilaporkan apa adanya, tanpa ambang yang dikarang) |
| C9 | Memori memenuhi skema brief §7; kontradiksi terdeteksi; pencabutan consent menonaktifkan memori dan membatalkan saran terbuka yang memakainya | tes integrasi |
| C10 | Mesin kualitas memberi status per sinyal per hari; interval tanpa data tidak pernah dihitung sebagai tidak aktif | tes unit dan integrasi dengan fikstur tumpang tindih, basi, terlambat |
| C11 | Skenario demo 10 langkah dan 5 kasus negatif (data kurang, permintaan medis tidak aman, consent dicabut, data jam tangan ganda, alat/penyedia gagal) berjalan sebagai satu tes ujung-ke-ujung | `tests/e2e/demo-4.0.test.ts` |
| C12 | Koleksi Bruno mencakup setiap endpoint baru dan yang diubah | koleksi dijalankan terhadap stack uji |
| C13 (tidak memblokir, dilaporkan) | Rantai jam tangan nyata, TalkBack, perangkat kelas rendah | daftar periksa manual dengan bukti tangkapan; bila tidak dilakukan, label `UNVERIFIED` |

**Bukti yang wajib ada:** keluaran tes dari container uji pada commit yang sama, laporan per fase di `docs/reports/`, matriks status akhir dengan label §2.

**Dalam cakupan:** backend, aplikasi Android, skema dan migrasi, tes, Bruno, dokumentasi arsitektur dan API.

**Di luar cakupan:** iOS; aplikasi Wear OS (kecuali diputuskan lain di Q6); melatih model dari data pengguna; bandit kontekstual atau eksperimen uplift; klaim efektivitas klinis; menulis ulang ke React atau kerangka lain; layanan infrastruktur baru; deploy produksi; commit atau push.

**Kendala keras:** semua aturan `AGENTS.md` (Docker, tanpa commit, tanpa kredensial di berkas ter-track, Prisma, Better Auth, FigCraft dulu); tanpa diagnosis, dosis, eskalasi latihan, atau klaim jaminan; konten medis tidak dipublikasikan sebelum ditinjau; nilai tak diketahui = `NULL`; kode tanpa komentar.

**Asumsi:** (A1) Mistral tetap satu-satunya penyedia LLM dan embedding; (A2) pengguna yang ada dipetakan ke jalur T2DM tanpa kehilangan data; (A3) draf konten boleh dipakai di lingkungan uji dan demo dengan label draf.

**Dependensi:** klinisi peninjau (`BLOCKED`), jam tangan + ponsel (`UNKNOWN`), tinjauan hukum consent (`BLOCKED`), persetujuan etik untuk data perilaku (`BLOCKED`), tenggat hackathon (`UNKNOWN`, Q1).

**Kondisi berhenti:** semua kriteria memblokir lulus; atau sebuah perubahan menuntut pelonggaran batas keselamatan; atau migrasi tidak dapat dibuat reversibel; atau cakupan harus melebar di luar daftar di atas; atau FigCraft tidak dapat dipakai untuk pekerjaan UI. Pada keempat kasus terakhir saya berhenti dan melapor.

## 5. Arsitektur sasaran

```
Sensor / catatan manual / umpan balik
  → gerbang consent + mesin kualitas            (devices/quality, consent)
  → catatan domain terverifikasi                (tabel yang ada)
  → outbox beramplop, transaksi yang sama       (outbox_events + kolom amplop)
  → proyeksi perilaku harian                    (BARU: daily_behavior_facts)
  → konteks agen · tujuan · JITAI · sosial      (semua membaca proyeksi)
  → usulan aksi oleh skill terdaftar            (BARU: registri skill + FSM)
  → persetujuan eksplisit                       (decide(), kuitansi operationId)
  → pengamatan hasil                            (rekonsiliasi dipicu peristiwa)
  → pembaruan memori                            (memory_items diperluas + revisi)
  → keputusan intervensi berikutnya             (jitai-policy-v3)
```

Keputusan desain utama:

1. **Outbox tetap satu-satunya angkutan.** Ditambah kolom amplop (aditif, nullable). Catatan domain tetap sumber kebenaran; "putar ulang" berarti membangun ulang proyeksi dari catatan untuk rentang tanggal, bukan menyimpan log peristiwa selamanya.
2. **Satu proyeksi perilaku** per pengguna per tanggal lokal: menit aktif per tingkat kualitas, langkah, menit tidur, makan tercatat, pemeriksaan glukosa (jumlah saja), konfirmasi obat, sumber, cakupan, versi perhitungan. Konsumen dipindahkan satu per satu di balik tes paritas.
3. **Registri skill membungkus kode yang ada.** Graf gizi dan aktivitas menjadi isi skill, bukan ditulis ulang. Router regex tetap pertama.
4. **Pengetahuan publik dan data pribadi tidak pernah berbagi tabel.** Jalur A dan C di `knowledge_documents`/`knowledge_chunks`; jalur B tetap `food_reference`; jalur D dan E lewat kueri terstruktur yang memfilter `user_id` lebih dulu.
5. **Tidak ada nilai tersimpan yang diganti nama.** Kosakata baru (hasil, kelas keputusan, keadaan Spark) dipetakan di lapisan tampilan agar migrasi reversibel.

## 6. Rencana per fase

Setiap fase ditutup dengan: daftar berkas, hasil tes dari container, pembaruan Bruno dan dokumen, apa yang terverifikasi, dan gerbang rilis yang masih tertutup. Saya berhenti di akhir tiap fase agar bisa di-commit pemilik.

### P0 — Audit repositori (selesai dengan dokumen ini)

Sisa kecil bila disetujui: jalankan koleksi Bruno yang ada terhadap stack uji dan catat hasilnya; perbarui `AGENTS.md` bagian "Cakupan saat ini".

### P1 — Kohort dan penyatuan peristiwa

**Tujuan:** C2, C3, C4.

| Langkah | Isi | Berkas utama |
|---|---|---|
| 1.1 Kebijakan kohort | Modul murni `cohort.policy.ts`: `PREVENTION`, `T2DM_SUPPORT`, `WELLNESS`, `UNDETERMINED`. Masukan: pernyataan pengguna (diagnosis T2DM; "dokter/nakes pernah menyatakan prediabetes atau berisiko"; tujuan kebugaran), usia. Tidak ada penetapan otomatis dari data. T1DM, di bawah 18 tahun, atau tidak jelas → `UNDETERMINED` (pencatatan saja, tanpa coaching) | `server/src/features/cohort/*` (baru), `health-profile/eligibility.ts` |
| 1.2 Skema | `health_profiles`: kolom `journey`, `journey_source`, `journey_set_at`; nilai baru `diagnosis_status`. Isi mundur: `eligible` lama → `T2DM_SUPPORT`, lainnya `UNDETERMINED`. Migrasi turun disertakan | `prisma/schema.prisma`, migrasi `p12_cohort` |
| 1.3 Pemisahan konten | `allowedCohorts` pada edukasi, strategi, sumber coaching, pesan keselamatan, prompt pengklasifikasi (tidak lagi menyebut T2DM), kartu Beranda. Fitur glukosa dan obat disembunyikan bawaan di `WELLNESS`; pengingat skrining dan rujukan untuk `PREVENTION` (teks draf, perlu klinisi) | `education`, `coaching`, `conversation`, `agent.safety.ts` |
| 1.4 Consent | Kebijakan `1.1`: teks netral-kohort; tujuan baru hanya bila diperlukan (Q4). Memicu `reconsent_required` | `consent/consent.policy.ts` |
| 1.5 Amplop peristiwa | `outbox_events` + `source, source_record_id, occurred_at, received_at, timezone, revision, consent_scope, quality, provenance, correlation_id`. Pembantu `emitRecordEvent(tx, …)` | `infrastructure/queue/outbox.ts`, migrasi `p12_event_envelope` |
| 1.6 Penerbit | `record.created/corrected/archived` dari makan, glukosa, aktivitas, asupan obat, check-in tujuan, vital, impor perangkat (langkah, tidur, latihan); `consent.withdrawn`; `memory.changed` | layanan domain terkait |
| 1.7 Registri penangan | Ganti peta `outcomes.handlers` dengan registri per fitur; tiap penangan idempoten | `infrastructure/queue/handlers.ts` (baru) |
| 1.8 Proyeksi | `daily_behavior_facts` + pembangun ulang dari catatan; penangan memperbarui hari terdampak; sinkron terlambat menandai hari untuk dihitung ulang | `features/projections/*` (baru), migrasi |
| 1.9 Pindahkan konsumen | Komunitas (hari aktif), coaching (hari terlaksana), hasil agen, alat `get_activity_context` membaca proyeksi. Tes paritas dulu, baru ganti | `community.service.ts`, `coaching.service.ts`, `agent/outcomes.ts`, `agent.tools.ts` |
| 1.10 Kosakata hasil | `outcome.vocabulary.ts`: pemetaan ke `ACCEPTED, REJECTED, SELF_REPORTED, OBSERVED, NOT_OBSERVED, RETRACTED, UNKNOWN` | baru |
| 1.11 Aplikasi | Langkah onboarding "jalur", layar ubah jalur, Beranda per jalur. **FigCraft dulu** | `app/lib/features/{onboarding,health_profile,home}` |

**Tes:** matriks kohort; idempotensi peristiwa (duplikat, urutan terbalik, serentak); koreksi dan arsip memicu hitung ulang; putar ulang = identik; paritas konsumen; pencabutan consent menerbitkan peristiwa dan membatalkan saran terbuka tanpa menunggu dibaca.

**Rollback:** migrasi turun untuk tiga migrasi; konsumen punya sakelar `projection_consumers` untuk kembali ke perhitungan lama selama masa paritas.

**Tidak terverifikasi di akhir P1:** teks jalur pencegahan (klinisi), teks consent 1.1 (hukum).

### P2 — Orkestrasi cerdas

**Tujuan:** C5–C9.

| Langkah | Isi |
|---|---|
| 2.1 Registri skill | `features/agent/skills/registry.ts` dengan tipe `Skill` berisi seluruh atribut brief §4. Delapan skill: `nutrition.coach`, `activity.planner`, `sleep.recovery`, `behavior.barrier_solver`, `prevention.education`, `health.trend_explainer`, `social.challenge_coach`, `memory.reflector`. Enam membungkus kode yang ada; `sleep.recovery` dan `prevention.education` baru dan hanya deskriptif + edukasi |
| 2.2 Kebijakan pemilihan | `selectSkills(route, cohort, consents, flags)` → daftar skill sah atau penolakan beralasan. Enum pengklasifikasi LLM dibangkitkan dari registri, jadi model hanya bisa mengusulkan skill terdaftar |
| 2.3 Tingkat alat | Atribut `tier` pada alat. Alat `USER_CONFIRMED` (buat rencana, simpan preferensi, simpan memori, ikut tantangan, ubah pengingat) didaftarkan di registri yang sama dan hanya dapat dijalankan dari keadaan `EXECUTE_AUTHORIZED_ACTION` dengan kuitansi `operationId`. Daftar `PROHIBITED` dijaga tes negatif |
| 2.4 Mesin keadaan | `agent.fsm.ts`: 16 keadaan brief §5, tabel transisi, anggaran (3 iterasi, 8 alat, batas waktu run, anggaran token, 1 kali ulang), pembatalan dan kompensasi. Transisi dicatat di `agent_run_events`; `agent_runs` mendapat `skill_id`, `skill_version`, `iterations` |
| 2.5 Iterasi terbatas | `EVALUATE` menilai cakupan bukti; bila kurang dan anggaran tersisa, perencana deterministik memilih alat baca berikutnya dari `allowedTools` skill. Usulan langkah dari LLM: sakelar `react_llm_planner`, bawaan mati, mode bayangan dulu (usulan dicatat, tidak dijalankan) |
| 2.6 Multi-intent | Maksimum 2 skill per pesan, urutan dependensi eksplisit di registri (`after`), tiap skill dengan anggaran sendiri; gagal satu tidak membatalkan yang lain |
| 2.7 Pengetahuan | Tabel `knowledge_documents` (metadata brief §6) dan `knowledge_chunks` (teks, tsvector, `vector`). Ingest: 10 modul edukasi → jalur A; 14 strategi → jalur C; status mengikuti tinjauan |
| 2.8 Pipa retrieval | `features/knowledge/retrieval.ts`: normalisasi → filter jalur/kohort/bahasa/status/kedaluwarsa → leksikal → vektor → RRF (pakai fungsi yang ada) → filter kesegaran → rerank opsional (mati) → penilaian cakupan → jawab berdasar bukti atau abstain. Web hanya menghasilkan kandidat rujukan berstatus `CANDIDATE`, tidak pernah disajikan sebagai panduan |
| 2.9 Label kepastian | Satu enum `verified / reported / estimated / insufficient / unknown` dipakai di semua balasan faktual, dipetakan dari provenans yang ada |
| 2.10 Memori | `memory_items` + `memory_type, source_ids, valid_from, last_verified_at, privacy_scope, conflict_state, superseded_by, paused_at`; tabel `memory_revisions`. Memori turunan dihitung dari proyeksi (mis. waktu aktif tersering) dan **selalu diusulkan** sebelum dipakai. Detektor kontradiksi. `memory.retrieve(userId, skill, budget)` dengan filter consent, prioritas terkonfirmasi dan terbaru, batas jumlah butir. Setiap saran menyimpan ID memori yang dipakai |
| 2.11 Kendali | Jeda per butir; pencabutan consent → memori dijeda, usulan dihapus, saran terbuka yang memakainya dibatalkan (lewat peristiwa `consent.withdrawn`) |
| 2.12 Aplikasi | Layar memori: tipe, sumber, jeda, riwayat koreksi, konflik; kartu "berdasarkan apa" pada saran. **FigCraft dulu** |

**Tes:** skema registri; kebijakan pemilihan; properti FSM (tidak ada transisi di luar tabel, anggaran tidak terlampaui); injeksi lewat respons alat untuk tiap alat; isolasi jalur; evaluasi retrieval (`scripts/eval/retrieval-eval.ts`: recall@k dan MRR pada set berlabel, dilaporkan apa adanya); kebocoran memori lintas pengguna; penulisan memori tanpa konfirmasi; percakapan multi-sesi.

**Rollback:** sakelar `skill_registry` mengembalikan ke jalur `dispatch` lama; migrasi turun.

**Tetap tertutup:** jalur A dan C di produksi sampai klinisi meninjau; `react_llm_planner` sampai evaluasi bayangan dibaca pemilik.

### P3 — Perangkat dan kecerdasan perilaku

**Tujuan:** C10, sebagian C13.

| Langkah | Isi |
|---|---|
| 3.1 Provenans | Klien mengirim `dataOrigin` (paket aplikasi), metode perekaman, dan perangkat bila tersedia; kolom baru di langkah, tidur, sesi, vital, glukosa; skema impor menerima field opsional (kompatibel mundur) |
| 3.2 Mesin kualitas | `features/devices/quality.ts`: kesegaran, cakupan jendela, tumpang tindih antar-asal, duplikat lintas sumber (manual vs perangkat), sinkron terlambat, nilai tak wajar. Keluaran per sinyal per hari. Tidak ada data = `UNKNOWN` |
| 3.3 Status | `GET /api/me/devices/status`: izin, sinkron terakhir, cakupan 14 hari per sinyal; layar status di aplikasi (**FigCraft dulu**) |
| 3.4 Validasi perangkat | Protokol uji tertulis; uji sintetis lewat Health Connect di emulator (Level 1); uji ponsel + jam tangan nyata bila tersedia. Tanpa perangkat: `UNVERIFIED` |
| 3.5 Fitur perilaku | Skema fitur berversi dari proyeksi dan log keputusan (tanpa nilai klinis) |
| 3.6 Baseline | Penilai deterministik `baseline-v1` untuk waktu aksi dan respons notifikasi (laju historis per slot dengan pemulusan). Didaftarkan di registri model, status `SHADOW`; keluaran dicatat, **tidak** memengaruhi keputusan |
| 3.7 Harness evaluasi | Pembagian per pengguna dan waktu, pemeriksaan kebocoran, Brier, PR-AUC, kalibrasi, analisis data hilang, drift. Diuji dengan fikstur sintetis **hanya untuk membuktikan pipa benar**, bukan untuk mengklaim kinerja |
| 3.8 JITAI v3 | Fungsi murni baru: masukan fakta proyeksi beserta kualitasnya, energi/lelah yang dilaporkan pengguna (check-in opsional satu ketukan), riwayat intervensi. Kelas: `INTERVENE, DEFER, ASK_FOR_CLARIFICATION, WITHHOLD, NO_INTERVENTION`. `WITHHOLD` saat data tidak andal, pengguna lelah/kurang sehat, atau keselamatan. Jam tenang, batas, dan jeda v2 dipertahankan dan diuji ulang |
| 3.9 Preferensi strategi | Hasil rencana memperbarui preferensi strategi dan slot hanya dari hasil `OBSERVED` berkualitas baik atau ≥ N `SELF_REPORTED`; N adalah hipotesis produk yang didokumentasikan |

**Tidak dibangun:** model terlatih, bandit, uplift. Syarat membuka: data pilot, consent pelatihan, persetujuan etik.

### P4 — Sosial dan pengalaman

**Tujuan:** bagian sosial dan UI dari C11.

| Langkah | Isi |
|---|---|
| 4.1 Desain | Halaman FigCraft baru: Beranda adaptif, kartu langkah berikutnya, keadaan Spark, layar tantangan baru, arah visual. Persetujuan pemilik atas arah visual sebelum kode (Q5) |
| 4.2 `score-v2` | Dari proyeksi: usaha terverifikasi, konsistensi, kemajuan terhadap diri sendiri. Batas harian, bobot catatan manual vs perangkat, hari istirahat. Tantangan berjalan tetap `score-v1` sampai selesai |
| 4.3 Bentuk baru | Rekor pribadi (tanpa peringkat publik); kelompok sebaya sepadan berdasarkan pita aktivitas dasar, minimum 5 anggota, jatuh ke tanpa peringkat bila kurang; misi konsistensi tim; pengakuan kembali-setelah-jeda; rekomendasi tantangan opt-in lewat `social.challenge_coach` |
| 4.4 Lingkar | Peristiwa tantangan masuk outbox dan, bila consent ada, ke episode mingguan dan memori |
| 4.5 Spark | Tambah `awaitingConfirmation` dan `safetyWarning`; pemetaan ke 6 keadaan brief; hormati kurangi-gerak |
| 4.6 Beranda | `GET /api/me/today/next-action`: satu langkah berikutnya dari sumber yang sudah ada (persetujuan tertunda, rencana jatuh tempo, intervensi, refleksi). Alur `TODAY → NEXT ACTION → CONFIRM → PROGRESS → REFLECTION → INSIGHTS → CHALLENGES`. Metadata teknis dipindah ke lembar detail |
| 4.7 Keadaan | Memuat, berhasil, gagal, dan luring untuk setiap aksi baru |
| 4.8 Aksesibilitas | Tes teks 2× dan kontras untuk layar baru; TalkBack dan ponsel kelas rendah secara manual |

**Larangan yang diuji:** tidak ada glukosa, HbA1c, berat, kalori, diagnosis, atau volume latihan tak aman sebagai variabel peringkat.

### P5 — Evaluasi dan demonstrasi

| Langkah | Isi |
|---|---|
| 5.1 Suite adversarial | `tests/adversarial/`: injeksi (pesan, respons alat, multi-giliran), kebocoran lintas pengguna, IDOR, alat tanpa izin, penulisan memori tanpa izin, data perangkat basi, notifikasi ganda, percobaan ulang agen, keputusan serentak, pencabutan consent, privasi komunitas |
| 5.2 Multi-sesi | Skenario 3 sesi: memori dan hasil sesi 1 mengubah saran sesi 3 |
| 5.3 Cadangan | Uji pulih dari cadangan ke DB uji kosong |
| 5.4 Metrik | `scripts/eval/impact-metrics.ts` menghitung metrik brief §14 dari `usage_events` dan tabel domain. Tanpa pengguna nyata, keluaran hanya membuktikan perhitungannya berjalan |
| 5.5 Demo | `tests/e2e/demo-4.0.test.ts`: 10 langkah + 5 kasus negatif. Akun demo dibangkitkan saat dijalankan. Langkah "data jam tangan tiba" = muatan impor Health Connect; versi langsung memakai ponsel/jam tangan bila ada |
| 5.6 Gerbang klinis | Paket tinjauan diperbarui: konten pencegahan, strategi, pesan keselamatan, teks rujukan |
| 5.7 Laporan akhir | Matriks status berlabel, tabel level bukti, daftar gerbang rilis yang tertutup |

## 7. Risiko

| Risiko | Penanganan |
|---|---|
| Memindahkan konsumen ke proyeksi mengubah skor tantangan yang sedang berjalan | tes paritas; sakelar kembali; `score-v1` tidak disentuh untuk tantangan aktif |
| Volume outbox naik beberapa kali lipat; di Vercel dikuras tiap ~5 menit | indeks, batch, kuras langsung per pengguna setelah tulis, retensi peristiwa `DONE` |
| Perubahan kohort membingungkan pengguna lama | isi mundur ke T2DM; layar penjelasan satu kali; tidak ada data yang dihapus |
| Konten pencegahan ditulis tanpa klinisi | tetap draf, tersembunyi di produksi, berlabel di demo |
| Redesain visual merusak tes teks besar dan kontras | per layar, tes diperbarui bersama, tidak sekaligus |
| Cakupan terlalu besar untuk satu tenggat | urutan P1 → P2 → P5 (demo) memberi alur demo lengkap; P3 dan P4 dapat dipangkas (Q1) |

## 8. Keputusan yang saya perlukan dari pemilik

| # | Pertanyaan | Saran saya |
|---|---|---|
| Q1 | Kapan tenggat hackathon, dan apa yang wajib tampil? | Bila sempit: P1 → P2 → inti P3 (provenans + mesin kualitas + JITAI v3) → demo; sosial dan redesain visual menyusul |
| Q2 | Jalur pencegahan: cukup pernyataan pengguna "pernah dinyatakan prediabetes/berisiko oleh nakes", tanpa unggah bukti? | Ya. Tanpa kalkulator risiko otomatis |
| Q3 | Pengguna yang tidak cocok jalur mana pun (T1DM, di bawah 18): pencatatan saja tanpa coaching? | Ya, sama seperti `needs_review` sekarang |
| Q4 | Tujuan consent baru: (a) data perangkat dipakai untuk coaching, (b) hasil sosial masuk coaching/memori. Dipisah atau digabung ke `personalized_ai`? | Dipisah; keduanya opsional |
| Q5 | Arah visual "editorial sports, netral dingin": redesain palet menyeluruh, atau hanya layar baru? | Layar baru dan Beranda dulu; palet penuh setelah demo |
| Q6 | Aplikasi pendamping Wear OS? | Tidak di 4.0; Health Connect saja |
| Q7 | Adakah jam tangan dan ponsel untuk uji nyata, dan klinisi untuk tinjauan? | Tanpa keduanya label tetap `UNVERIFIED` / `REQUIRES_CLINICAL_REVIEW` |
| Q8 | Bekerja fase demi fase dengan berhenti untuk commit, atau terus P1 → P5? | Berhenti tiap fase |
| Q9 | Perbarui `AGENTS.md` ("Cakupan saat ini") di P1? | Ya |

## 9. Yang tidak akan diklaim

- Tidak ada klaim Level 2–4. Hasil 4.0 adalah Level 1.
- "Mendukung jam tangan" tidak ditulis tanpa uji perangkat nyata.
- Tidak ada angka kinerja model perilaku; yang ada hanya baseline dalam mode bayangan.
- Konten medis tetap berlabel draf sampai ada nama peninjau dan tanggal tinjauan.
