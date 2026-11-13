# beOkay 4.0 — Laporan implementasi

Tanggal: 13 November 2026. Basis: `main` @ `1305f83` + perubahan kerja yang belum di-commit. Goal: `beokay-4.0` v1 di [rencana](beokay-4.0-audit-and-plan.md) §4. Arsitektur: [`docs/architecture/beokay-4.0-ecosystem.md`](../architecture/beokay-4.0-ecosystem.md). API: [`docs/api/ecosystem-4.0.md`](../api/ecosystem-4.0.md). Desain: halaman `33 — beOkay 4.0` di `design/beOkay-ui-v3.figcraft`, ekspor `design/exports/33-*.png`.

Keputusan §8 tidak dijawab pemilik, jadi yang dipakai adalah saran di rencana. Satu pengecualian, Q8: pemilik meminta "end to end", sehingga pekerjaan berjalan tanpa berhenti per fase. Tahap kedua (UI, misi tim, check-in energi, memori turunan, perencana bayangan, uji pulih cadangan, Bruno lama) dikerjakan atas permintaan pemilik untuk melanjutkan implementasi.

## 1. Hasil verifikasi

Backend dijalankan di stack uji Docker terisolasi (`compose.test.yaml`, DB tmpfs); Flutter di host sesuai aturan proyek. Semua pada pohon kerja yang sama.

| Pemeriksaan | Hasil |
|---|---|
| `bun test` (backend) | **460 lulus, 0 gagal**, 80 berkas (406 tes lama + 54 baru) |
| `bun run typecheck` | bersih |
| `prisma migrate diff` | hanya noise yang diizinkan (didokumentasikan di `AGENTS.md`) |
| Rollback `p14`, `p13`, `p12`, lalu `db:migrate:deploy` lagi | berhasil; tabel baru hilang lalu kembali (p12/p13 diuji bersama, p14 terpisah) |
| Uji pulih cadangan (`server/scripts/ops/backup-restore-check.sh`) | **OK**: 88 tabel, 266 baris, ekstensi `pg_trgm, plpgsql, vector` identik setelah `pg_dump` → `pg_restore`. DB uji berisi sedikit baris karena tes membersihkan datanya; uji ini membuktikan prosedur, bukan ukuran data produksi |
| Bruno seluruh koleksi, folder 08–20 (CLI 2.3.0, akun sintetis dibangkitkan saat runtime) | **120/120 permintaan dan tes lulus**. Butuh tiga perbaikan koleksi lama (§1.2) |
| `flutter test` | **249 lulus** (237 lama + 12 baru) |
| `flutter analyze` | tanpa temuan |
| Retrieval, set dev (18 kueri, k=3) | recall@3 1,000; MRR 1,000; 2/2 abstain benar. **In-sample**: putaran pertama 0,875, dan set ini memicu penambahan kosakata hambatan dan stopword |
| Retrieval, set **held-out** (18 kueri ditulis setelah penyetelan, tidak dipakai menyetel) | recall@3 **0,833**; MRR **0,80**; 3/3 abstain benar; 0 jawaban salah untuk kueri di luar topik. Dua yang meleset: "keringat dingin dan gemetar setelah minum obat" (modul obat/glukometer, bukan hipoglikemia) dan "pulang kerja badanku lemas sekali" (abstain, tidak menemukan strategi tenaga) |
| `scripts/eval/behavior-eval.ts` (40 pengguna sintetis) | kebocoran 0; Brier 0,084; PR-AUC 0,72; ECE 0,040; PSI 0,041. Fikstur sintetis, **bukan kinerja model** |
| `scripts/eval/impact-metrics.ts` | berjalan di DB uji; angka hanya membuktikan perhitungannya berjalan |

Tes lama yang diubah, semuanya karena perubahan perilaku yang disengaja: jumlah modul edukasi (10 → 13; T2DM melihat 11), daftar alat (7 → 11), tabel ekspor (`memory_revisions` dan `daily_checkins` diekspor, `daily_behavior_facts` dikecualikan), uji outbox (peristiwa `consent.granted` baru dikecualikan dari hitungan; pengurasan memakai registri baru), dan versi kebijakan intervensi (`jitai-policy-v3`). Satu tes lama ternyata flaky dan diperbaiki: `phase8 D-1` memeriksa "112" pada JSON yang memuat UUID acak, sehingga gagal bila UUID kebetulan mengandung "112".

### 1.1 Flutter

Berkas aplikasi yang diubah atau ditambah: Spark (dua keadaan baru), profil kesehatan (pernyataan risiko), fitur `journey`, fitur `next_action`, memori, status perangkat, part Asisten `evidence`/`strategy`, misi tim, serta impor Health Connect (`dataOrigin`, `recordingMethod`). Tes baru `test/flows/beokay4_test.dart` (12 tes) mencakup desain A–J dan pemetaan keadaan Spark.

### 1.2 Bruno

Koleksi lama belum pernah dijalankan ulang sejak 3.0. Jalan pertama memberi 114/120, dan tidak satu pun kegagalan berasal dari perubahan 4.0:

- Uji ekspor mengharapkan `beokay-export-v1`, padahal server memakai `v4` sejak 3.0. Ekspektasi diperbarui.
- Nutrition/14 "lintas pengguna" memakai token terbatas, padahal uji "tanpa consent" di folder Medication/Sync mengharuskan token itu tanpa consent sama sekali. Uji ini kini memakai `otherSessionToken`, seperti uji lintas pengguna di folder lain.
- Folder Sync memakai ulang `newGlucoseId` yang sudah dipakai folder Glucose, sehingga server menjawab CONFLICT. Folder Sync kini memakai `syncGlucoseId` sendiri.

Daftar variabel runtime ada di [`docs/api/ecosystem-4.0.md`](../api/ecosystem-4.0.md#menjalankan-koleksi-bruno).

## 2. Kriteria goal

| ID | Kriteria | Status | Bukti |
|---|---|---|---|
| C1 | Tanpa regresi | **TESTED** | §1 |
| C2 | Kohort dan pemisahan konten | **TESTED** | `tests/unit/p12-cohort-projection.test.ts`, `p12-ecosystem` C2, Bruno 20/03–06, Flutter 4.0-A/B |
| C3 | Satu peristiwa beramplop per catatan, transaksi sama, idempoten, putar ulang identik | **TESTED** | `p12-ecosystem` C3, C3/C4; check-in energi di `p14-additions` |
| C4 | Satu proyeksi untuk hari aktif; konsumen membacanya | **TESTED (sebagian konsumen)** | paritas komunitas (unit) dan coaching (integrasi); misi tim dan `score-v2` membaca proyeksi. `outcomes.reconcile` dan `explainWhy` sengaja tetap membaca catatan (pencocokan per sesi, bukan agregasi) |
| C5 | Registri 8 skill; pemilihan di luar registri, jalur, atau consent ditolak dan dicatat | **TESTED** | `p13-skills-fsm` registri, `p12-ecosystem` C5/C6 |
| C6 | FSM, ≤3 iterasi, ≤8 alat, `USER_CONFIRMED` hanya dengan kuitansi | **TESTED** | 2.000 jalan acak; `FSM_DECISION` dengan `receipt`; `REQUIRES_CONFIRMATION`/`PROHIBITED`; perencana bayangan tidak menambah panggilan alat |
| C7 | Suite adversarial 0 pelanggaran | **TESTED** | `tests/adversarial/agent-adversarial.test.ts` (8 skenario). Satu temuan nyata saat menulisnya: potongan pengetahuan yang disuntik lolos ke balasan, lalu ditambah penyaringan keluaran alat (`sanitize`) |
| C8 | Isolasi jalur retrieval; label kepastian atau abstain | **TESTED** | `p12-ecosystem` C8, Bruno 20/14, evaluasi dev dan held-out |
| C9 | Memori: skema, kontradiksi, kaskade pencabutan | **TESTED** | `p12-ecosystem` C9, memori turunan di `p14-additions`, Flutter 4.0-E |
| C10 | Mesin kualitas; tanpa data ≠ tidak aktif | **TESTED** | `p13-skills-fsm` device-quality, Bruno 20/08–09, ADV-7, Flutter 4.0-F |
| C11 | Demo 10 langkah + 5 kasus negatif | **TESTED (API + widget)** | `tests/e2e/demo-4.0.test.ts`; layar terkait diuji per widget di Flutter. Langkah "data jam tangan" = muatan impor Health Connect sintetis; belum dijalankan di ponsel |
| C12 | Bruno untuk endpoint baru dan berubah | **TESTED** | seluruh koleksi 120/120 |
| C13 | Jam tangan nyata, TalkBack, ponsel kelas rendah | **UNVERIFIED** | tidak ada perangkat tersambung (`adb devices` kosong) |

## 3. Matriks status per bagian brief

| Bagian | Status | Catatan |
|---|---|---|
| Tiga jalur + kelayakan | BUILT, TESTED | pernyataan pengguna saja; isi mundur pengguna lama; layar profil dan "Jalurmu" |
| Teks dan edukasi pencegahan | BUILT, REQUIRES_CLINICAL_REVIEW | 3 modul draf baru |
| Peristiwa beramplop | BUILT, TESTED | 10 jenis catatan (termasuk check-in energi) + 7 jenis peristiwa domain |
| Proyeksi harian | BUILT, TESTED | baca-tembus dengan tanda kotor |
| Registri skill (8) | BUILT, TESTED | 3 skill baru deskriptif; 5 membungkus kode 3.0 |
| FSM berbatas | BUILT, TESTED | run 3.0 dicatat lewat jalur turunan; skill baru loop berbatas |
| Perencana LLM (ReAct) | BUILT (mode bayangan), TESTED | `react_llm_planner` bawaan mati; usulan dicatat, tidak pernah dijalankan; kecocokan belum dievaluasi pada data nyata |
| Multi-intent | PARTIAL | maks. 2, hanya untuk skill deskriptif baru |
| Tingkat alat | BUILT, TESTED | 11 baca, 7 butuh konfirmasi, 10 terlarang |
| RAG jalur A/C | BUILT, TESTED | produksi abstain sampai ada konten `REVIEWED` |
| Embedding pengetahuan | BUILT, UNVERIFIED | jalur vektor tidak berjalan di uji (tanpa kunci Mistral) |
| Label kepastian | BUILT, TESTED | dipakai skill baru dan ditampilkan sebagai chip; jawaban gizi/aktivitas 3.0 tetap memakai label provenans lama |
| Memori lintas sesi | BUILT, TESTED | termasuk memori turunan (usulan rutinitas dari catatan) dan layar jeda/konflik/riwayat |
| Provenans perangkat | BUILT, TESTED | aplikasi mengirim `dataOrigin` dan `recordingMethod`; langkah agregat tetap tanpa asal data |
| Mesin kualitas + status | BUILT, TESTED | layar status perangkat |
| Uji jam tangan nyata | UNVERIFIED | |
| Fitur perilaku + baseline bayangan | BUILT, TESTED | `baseline-v1` SHADOW, tidak memengaruhi keputusan |
| Harness evaluasi | BUILT, TESTED | sintetis saja |
| Model terlatih / bandit / uplift | EXTERNALLY_BLOCKED | data pilot, consent pelatihan, izin etik |
| JITAI v3 | BUILT, TESTED | menerima energi dari check-in |
| Check-in energi | BUILT, TESTED | satu ketukan di Beranda; `LOW` menahan pengingat rencana proaktif |
| Preferensi strategi dari hasil (3.9) | NOT_IMPLEMENTED | |
| `score-v2`, rekor pribadi, sebaya ≥5, kembali-setelah-jeda | BUILT, TESTED | tantangan berjalan tetap `score-v1` |
| Misi tim | BUILT, TESTED | agregat hanya bila ≥5 peserta; templat 7 hari |
| Rekomendasi tantangan dari skill | NOT_IMPLEMENTED | `social.challenge_coach` hanya menjelaskan tantangan terbuka |
| Peristiwa tantangan ke outbox | BUILT, TESTED | pemakaian ke memori/episode: NOT_IMPLEMENTED |
| Langkah berikutnya + alur + keadaan Spark | BUILT, TESTED | API dan kartu Beranda |
| UI Flutter 4.0 | BUILT, TESTED (widget) | desain FigCraft A–J dulu; belum dicoba di ponsel |
| Consent 1.1 | BUILT, TESTED, REQUIRES_LEGAL_REVIEW | memicu `reconsent_required` untuk semua pengguna |
| Uji pulih cadangan | BUILT, TESTED | prosedur terbukti di DB uji |

## 4. Level bukti

Level 1 (fungsi teknis terbukti di lingkungan uji) untuk semua butir BUILT/TESTED. Tidak ada klaim Level 2–4: belum ada pengguna nyata, klinisi, maupun perangkat nyata.

## 5. Yang belum dikerjakan dan alasannya

1. **Uji di perangkat** (jam tangan + ponsel, TalkBack, ponsel kelas rendah): tidak ada perangkat tersambung. Semua UI baru baru teruji sebagai widget.
2. **Tinjauan klinis dan hukum**: lihat paket tinjauan.
3. **Preferensi strategi dari hasil, rekomendasi tantangan dari skill, memori dari hasil tantangan**: tidak dibangun.
4. **Evaluasi perencana bayangan**: butuh percakapan nyata dan kunci Mistral; sekarang hanya terbukti bahwa usulannya tercatat dan tidak dijalankan.
5. **Deploy produksi** di luar cakupan goal. Catatan untuk deploy:
   - tiga migrasi baru (`p12`, `p13`, `p14`);
   - consent 1.1 akan meminta semua pengguna menyetujui ulang;
   - APK baru diperlukan agar pengguna bisa memilih jalur pencegahan atau gaya hidup sehat.

## 6. Gerbang rilis yang tetap tertutup

- Konten jalur A/C di produksi sampai klinisi meninjau (paket: [`beokay-4.0-clinical-review-packet.md`](beokay-4.0-clinical-review-packet.md)).
- Teks consent 1.1 sampai tinjauan hukum.
- `react_llm_planner` tetap mati sampai tingkat kecocokan bayangan dibaca pemilik; bahkan bila menyala, usulannya tidak dijalankan.
- `baseline-v1` tetap SHADOW.
- "Mendukung jam tangan" tidak boleh diklaim sebelum uji perangkat nyata.

## 7. Berkas

Server:
- Fitur baru: `src/features/{cohort,events,projections,knowledge,checkins}/*`, `src/features/agent/{agent.fsm.ts,skills/*}` (termasuk `llm-planner.ts`), `src/features/devices/quality.*`, `src/features/interventions/intervention.policy.v3.ts`, `src/features/ml/behavior/*`, `src/features/community/scoring.v2.ts`, `src/features/today/next-action.service.ts`, `src/features/conversation/conversation.skills.ts`, `src/infrastructure/queue/events.ts`.
- Migrasi: tiga migrasi baru, skrip turun di `prisma/rollback/`.
- Skrip: `scripts/eval/*`, `scripts/ops/backup-restore-check.sh`.
- Tes: `tests/unit/p12-*`, `p13-*`, `p14-*`; `tests/integration/p12-ecosystem.test.ts`, `p14-additions.test.ts`; `tests/adversarial/`; `tests/e2e/demo-4.0.test.ts`; `tests/fixtures/retrieval-queries*.ts`.

Aplikasi:
- Fitur baru: `lib/features/{journey,next_action}/*`, `lib/features/devices/presentation/device_status_section.dart`.
- Diubah: Spark, profil kesehatan, profil, Beranda, memori, Asisten, tantangan, impor Health Connect.
- Tes: `test/flows/beokay4_test.dart`.

Desain dan dokumen:
- Desain: halaman 33 di `design/beOkay-ui-v3.figcraft`; ekspor `design/exports/33-*.png`.
- Bruno: folder 20 dan tiga perbaikan koleksi lama.
- Dokumen di atas, serta `AGENTS.md`.

Tidak ada commit. Pemilik yang melakukan commit.
