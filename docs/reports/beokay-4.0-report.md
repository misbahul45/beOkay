# beOkay 4.0 — Laporan implementasi

Tanggal: 13 November 2026. Basis: `main` @ `1305f83` + perubahan kerja yang belum di-commit. Goal: `beokay-4.0` v1 di [rencana](beokay-4.0-audit-and-plan.md) §4. Arsitektur: [`docs/architecture/beokay-4.0-ecosystem.md`](../architecture/beokay-4.0-ecosystem.md). API: [`docs/api/ecosystem-4.0.md`](../api/ecosystem-4.0.md).

Keputusan §8 tidak dijawab pemilik; yang dipakai adalah saran di rencana, kecuali Q8: pemilik meminta "end to end", jadi P1→P5 dikerjakan berurutan tanpa berhenti per fase. Q5 (arah visual) dan seluruh UI Flutter berhenti di gerbang desain FigCraft (lihat §5).

## 1. Hasil verifikasi

Semua dijalankan di stack uji Docker terisolasi (`compose.test.yaml`, DB tmpfs) pada pohon kerja yang sama.

| Pemeriksaan | Hasil |
|---|---|
| `bun test` (backend) | **454 lulus, 0 gagal**, 79 berkas (406 tes lama + 48 baru) |
| `bun run typecheck` | bersih |
| `prisma migrate diff` (skema vs DB termigrasi) | hanya noise yang diizinkan (didokumentasikan di `AGENTS.md`) |
| Rollback `p13` lalu `p12`, lalu `db:migrate:deploy` lagi | berhasil; tabel baru hilang lalu kembali |
| Bruno `20 - Ecosystem 4.0` (Bruno CLI 2.3.0, jaringan `beokay-test_default`, akun sintetis dibangkitkan saat runtime) | **14/14 permintaan, 14/14 tes lulus** |
| `flutter test`, `flutter analyze` | 237 lulus; tanpa temuan (§1.1) |
| `scripts/eval/retrieval-eval.ts` (18 kueri berlabel, k=3) | recall@3 = 1,000; MRR = 1,000; 2/2 abstain benar. **Catatan:** pada putaran pertama recall@3 0,875 dan 1 kueri di luar topik dijawab. Set yang sama memicu penambahan kosakata hambatan dan stopword, jadi angka akhir adalah in-sample, bukan estimasi umum |
| `scripts/eval/behavior-eval.ts` (40 pengguna sintetis) | kebocoran 0; Brier 0,084; PR-AUC 0,72; ECE 0,040; PSI 0,041. Fikstur sintetis: **bukan kinerja model** |
| `scripts/eval/impact-metrics.ts` | berjalan pada DB uji; angka hanya membuktikan perhitungan berjalan |

Tes lama yang diubah, semuanya karena perubahan perilaku yang disengaja: jumlah modul edukasi (10 → 13; T2DM melihat 11), daftar alat (7 → 11), tabel ekspor (`memory_revisions` diekspor, `daily_behavior_facts` dikecualikan), uji outbox (peristiwa `consent.granted` baru dikecualikan dari hitungan; pengurasan memakai registri baru), versi kebijakan intervensi (`jitai-policy-v3`). Satu tes lama ternyata flaky dan diperbaiki: `phase8 D-1` memeriksa "112" pada JSON yang memuat UUID acak, sehingga gagal bila UUID kebetulan mengandung "112".

### 1.1 Flutter

`flutter test`: **237 lulus** ("All tests passed!"). `flutter analyze`: **No issues found**. Dijalankan di host sesuai aturan proyek.

Tidak ada berkas `app/` yang diubah di 4.0.

## 2. Kriteria goal

| ID | Kriteria | Status | Bukti |
|---|---|---|---|
| C1 | Tanpa regresi | **TESTED** | §1 |
| C2 | Kohort dan pemisahan konten | **TESTED** | `tests/unit/p12-cohort-projection.test.ts`, `p12-ecosystem` C2, Bruno 03–06 |
| C3 | Satu peristiwa beramplop per catatan, transaksi sama, idempoten, putar ulang identik | **TESTED** | `p12-ecosystem` C3, C3/C4 |
| C4 | Satu proyeksi untuk hari aktif; konsumen membacanya | **TESTED (sebagian konsumen)** | paritas komunitas (unit) dan coaching (integrasi). `outcomes.reconcile` dan `explainWhy` sengaja tetap membaca catatan (pencocokan per sesi, bukan agregasi) |
| C5 | Registri 8 skill; pemilihan di luar registri/jalur/consent ditolak dan dicatat | **TESTED** | `p13-skills-fsm` registri, `p12-ecosystem` C5/C6 |
| C6 | FSM, ≤3 iterasi, ≤8 alat, `USER_CONFIRMED` hanya dengan kuitansi | **TESTED** | 2.000 jalan acak; `FSM_DECISION` dengan `receipt`; `REQUIRES_CONFIRMATION`/`PROHIBITED` |
| C7 | Suite adversarial 0 pelanggaran | **TESTED** | `tests/adversarial/agent-adversarial.test.ts` (8 skenario). Satu temuan nyata saat menulisnya: potongan pengetahuan yang disuntik lolos ke balasan → ditambah penyaringan keluaran alat (`sanitize`) |
| C8 | Isolasi jalur retrieval; label kepastian atau abstain | **TESTED** | `p12-ecosystem` C8, Bruno 14, evaluasi retrieval |
| C9 | Memori: skema, kontradiksi, kaskade pencabutan | **TESTED** | `p12-ecosystem` C9 (dua tes), Bruno 10–11 |
| C10 | Mesin kualitas; tanpa data ≠ tidak aktif | **TESTED** | `p13-skills-fsm` device-quality, Bruno 08–09, ADV-7 |
| C11 | Demo 10 langkah + 5 kasus negatif | **TESTED (API)** | `tests/e2e/demo-4.0.test.ts`. Langkah "data jam tangan" = muatan impor Health Connect sintetis; tanpa UI |
| C12 | Bruno untuk endpoint baru/berubah | **TESTED** | folder 20, 14/14. Folder lama 08–19 **tidak dijalankan ulang** (butuh fikstur berurutan) → `UNVERIFIED` untuk 4.0 |
| C13 | Jam tangan nyata, TalkBack, ponsel kelas rendah | **UNVERIFIED** | tidak ada perangkat dan tidak ada UI baru |

## 3. Matriks status per bagian brief

| Bagian | Status | Catatan |
|---|---|---|
| Tiga jalur + kelayakan | BUILT, TESTED | pernyataan pengguna saja; isi mundur pengguna lama |
| Teks dan edukasi pencegahan | BUILT, REQUIRES_CLINICAL_REVIEW | 3 modul draf baru |
| Peristiwa beramplop | BUILT, TESTED | 9 jenis catatan + 7 jenis peristiwa domain |
| Proyeksi harian | BUILT, TESTED | baca-tembus dengan tanda kotor |
| Registri skill (8) | BUILT, TESTED | 3 skill baru deskriptif; 5 membungkus kode 3.0 |
| FSM berbatas | BUILT, TESTED | run 3.0 dicatat lewat jalur turunan; skill baru loop berbatas |
| Perencana LLM (ReAct) | NOT_IMPLEMENTED | sakelar `react_llm_planner` bawaan mati (T7) |
| Multi-intent | PARTIAL | maks. 2, hanya untuk skill deskriptif baru |
| Tingkat alat | BUILT, TESTED | 11 baca, 7 butuh konfirmasi, 10 terlarang |
| RAG jalur A/C | BUILT, TESTED | produksi abstain sampai ada konten `REVIEWED` |
| Embedding pengetahuan | BUILT, UNVERIFIED | jalur vektor tidak berjalan di uji (tanpa kunci Mistral) |
| Label kepastian | BUILT, TESTED | dipakai skill baru; jawaban gizi/aktivitas 3.0 tetap memakai label provenans lama |
| Memori lintas sesi | BUILT, TESTED | memori turunan otomatis dari proyeksi: NOT_IMPLEMENTED |
| Provenans perangkat | BUILT, TESTED | `dataOrigin` dll. opsional; aplikasi belum mengirimnya |
| Mesin kualitas + status | BUILT, TESTED | |
| Uji jam tangan nyata | UNVERIFIED | |
| Fitur perilaku + baseline bayangan | BUILT, TESTED | `baseline-v1` SHADOW, tidak memengaruhi keputusan |
| Harness evaluasi | BUILT, TESTED | sintetis saja |
| Model terlatih / bandit / uplift | EXTERNALLY_BLOCKED | data pilot, consent pelatihan, izin etik |
| JITAI v3 | BUILT, TESTED | check-in energi belum ada di aplikasi |
| Preferensi strategi dari hasil (3.9) | NOT_IMPLEMENTED | |
| `score-v2`, rekor pribadi, sebaya ≥5, kembali-setelah-jeda | BUILT, TESTED | tantangan berjalan tetap `score-v1` |
| Misi tim, rekomendasi tantangan | NOT_IMPLEMENTED | |
| Peristiwa tantangan ke outbox | BUILT, TESTED | pemakaian ke memori/episode: NOT_IMPLEMENTED |
| Langkah berikutnya + alur + keadaan Spark (API) | BUILT, TESTED | |
| UI Flutter 4.0 (jalur, memori, status perangkat, kartu langkah berikutnya, Spark baru) | NOT_IMPLEMENTED | berhenti di gerbang FigCraft |
| Consent 1.1 | BUILT, TESTED, REQUIRES_LEGAL_REVIEW | memicu `reconsent_required` untuk semua pengguna |
| Uji pulih cadangan (5.3) | NOT_IMPLEMENTED | |

## 4. Level bukti

Level 1 (fungsi teknis terbukti di lingkungan uji) untuk semua butir BUILT/TESTED. Tidak ada klaim Level 2–4: tidak ada pengguna nyata, tidak ada klinisi, tidak ada perangkat nyata.

## 5. Yang belum dikerjakan dan alasannya

1. **UI Flutter.** Aturan proyek: desain di FigCraft dulu. MCP `figcraft` gagal tersambung di sesi ini (`CONNECTION_CLOSED`); `figcraft-cli` ada, tetapi membuat halaman desain baru adalah tahap tersendiri (perlu generator tata letak). Akibatnya pengguna aplikasi **belum bisa memilih jalur pencegahan atau gaya hidup** (field `riskStatement` belum ada di layar), belum melihat layar memori/status perangkat, dan belum mendapat kartu langkah berikutnya. API-nya siap dan teruji.
2. **Folder Bruno lama** tidak dijalankan ulang.
3. **Uji pulih cadangan, misi tim, rekomendasi tantangan, memori turunan otomatis, preferensi strategi dari hasil, check-in energi**: tidak dibangun.
4. **Deploy produksi** di luar cakupan goal. Catatan untuk deploy: dua migrasi baru, consent 1.1 akan meminta semua pengguna menyetujui ulang, dan aplikasi yang sudah terpasang belum menampilkan dua tujuan consent baru secara khusus (daftar tujuan dibaca dari kebijakan).

## 6. Gerbang rilis yang tetap tertutup

- Konten jalur A/C di produksi sampai klinisi meninjau (paket: [`beokay-4.0-clinical-review-packet.md`](beokay-4.0-clinical-review-packet.md)).
- Teks consent 1.1 sampai tinjauan hukum.
- `react_llm_planner` sampai evaluasi bayangan dibaca pemilik (dan sampai ada implementasinya).
- `baseline-v1` tetap SHADOW.
- "Mendukung jam tangan" tidak boleh diklaim sebelum uji perangkat nyata.

## 7. Berkas

Baru: `server/src/features/{cohort,events,projections,knowledge}/*`, `server/src/features/agent/{agent.fsm.ts,skills/*}`, `server/src/features/devices/quality.*`, `server/src/features/interventions/intervention.policy.v3.ts`, `server/src/features/ml/behavior/*`, `server/src/features/community/scoring.v2.ts`, `server/src/features/today/next-action.service.ts`, `server/src/features/conversation/conversation.skills.ts`, `server/src/infrastructure/queue/events.ts`, dua migrasi + `server/prisma/rollback/`, `server/scripts/eval/{retrieval,behavior}-eval.ts` dan `impact-metrics.ts`, tes `tests/unit/p12-*`, `p13-*`, `p14-*`, `tests/integration/p12-ecosystem.test.ts`, `tests/adversarial/`, `tests/e2e/demo-4.0.test.ts`, `tests/fixtures/retrieval-queries.ts`, Bruno folder 20, dokumen di atas. Diubah: layanan domain (penerbit peristiwa), percakapan, agen, coaching, komunitas, consent, memori, intervensi, edukasi, ekspor, sakelar, `AGENTS.md`.

Tidak ada commit. Pemilik yang melakukan commit.
