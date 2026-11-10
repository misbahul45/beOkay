# Laporan P2 (lanjutan) — 9–10 November 2026

## Klasifikasi: `P2_FUNCTIONALLY_COMPLETE_WITH_LIMITATIONS`

Seluruh irisan inti P2 sekarang ada, diuji otomatis, dan dijalankan di emulator Android: **agen nutrisi + aktivitas dengan persetujuan tepat sekali, personalisasi deterministik, komunitas/tantangan/papan peringkat dengan privasi kohort, dan model pengenal hidangan yang dilatih di Kaggle dan dideploy di Modal dalam mode bayangan.** Klasifikasi tidak `P2_COMPLETE` karena ada item master prompt yang sengaja/belum dikerjakan (bagian H) dan model tetap `RESEARCH_ONLY`. Tidak ada yang di bawah ini boleh dibaca sebagai "P2 selesai tanpa catatan".

## A. Ringkasan
Sebelum sesi: hanya RAG TKPI, preferensi/alergi, dan pengingat (P1). Sekarang tambahan:
runtime agen state-machine di PostgreSQL, registri alat deny-by-default, keselamatan deterministik, rekomendasi nutrisi **dan aktivitas** dengan persetujuan idempoten, rencana makan/aktivitas (bukan konsumsi/sesi), personalisasi berversi, komunitas berbasis provinsi, tantangan hari-aktif dengan ledger skor append-only, papan peringkat opt-in dengan penekanan kohort kecil, registri model + klien Modal + audit inferensi, dan layar Flutter untuk semuanya.

## B. Perubahan nyata
| Modul | Perubahan | Bukti |
|---|---|---|
| Runtime agen | `agent_runs/events/tool_calls`; pemulihan run macet (120 dtk), kedaluwarsa 24 jam, pembatalan | tes integrasi |
| Alat | 6 alat berkontrak (preferensi, personalisasi, TKPI, katalog pengguna, konteks aktivitas, tujuan perilaku); anggaran 8/run | tes integrasi + unit |
| Keselamatan | `safety-policy-v1` (obat/dosis, diagnosis, klaim kesehatan, pembatasan ekstrem, gejala darurat, nyeri/cedera, eskalasi intensitas) | unit + integrasi |
| Nutrisi | usulan bersumber (TKPI/katalog) → persetujuan → `planned_meals` → umpan balik | tes + emulator |
| **Aktivitas** | kandidat dari riwayat sesi pengguna sendiri, tanpa eskalasi intensitas → `activity_plans`; selesai/lewati | tes + **emulator** (rencana → "Selesai" → status COMPLETED di DB, tidak membuat sesi aktivitas) |
| Personalisasi | `pref-rules-v1`, penalti 0,6 × bobot, dapat dihapus | tes |
| Consent | 5 tujuan opsional baru (`personalized_ai`, `community_membership`, `challenge_participation`, `leaderboard_visibility`, `model_inference`), tanpa naik versi kebijakan | tes + emulator |
| **Komunitas** | 38 provinsi, alias unik (tanpa surel/telepon), bergabung/keluar, penekanan jumlah anggota < 5 | tes + **emulator** |
| **Tantangan & skor** | `score-v1` (50 hari aktif, 30 check-in, 20 partisipasi), ledger append-only (trigger menolak UPDATE), rekonsiliasi saat baca | tes + **emulator** (skor 22,5 → 23,6 setelah check-in; baris ledger diperiksa di DB) |
| **Papan peringkat** | hanya alias + skor + peringkat; ditekan bila kohort < 5; opt-in; skema tanpa FK ke tabel kesehatan | tes + emulator (ditekan, kohort 1) |
| **ML** | `model_versions`, `ml_inference_runs`, klien Modal (HTTPS `*.modal.run`, bearer, retry sekali, circuit breaker, validasi respons + kecocokan SHA/versi), mode bayangan | tes + **emulator + endpoint nyata** |
| Flutter | `CoachScreen` (nutrisi+aktivitas), `CommunityScreen`, `ChallengeListScreen`, `ChallengeDetailScreen`, kartu persetujuan | tes widget (Asisten 6, komunitas/tantangan 5) + emulator |

API baru: `/api/me/agent/*`, `/api/me/planned-meals`, `/api/me/activity-plans`, `/api/me/personalization`, `/api/regions`, `/api/me/communities[...]`, `/api/me/challenges/:id/{join,leave,visibility,checkins,progress,leaderboard}`, `GET /api/me/ml/models`.
Migrasi: `20261109100000_agent_recommendations`, `…100100_consent_personalized_ai`, `…110000_community`, `…120000_activity_plans`, `…130000_ml_registry` (semuanya sudah diterapkan ke DB dev dan uji).

## C. Pelatihan Kaggle dan deploy Modal (bukti nyata)
**Pelatihan** (kernel `misbahulmuttaqin/beokay-dish-classifier`, GPU, 636 dtk, 8 epoch, MobileNetV3-Large, bobot awal ImageNet-1k, seed 1337), dataset `rizkyyk/dataset-food-classification`, 13 kelas:
| Ukuran | Nilai |
|---|---|
| Akurasi uji penuh (n=647) | 0,9691 (top-3 0,9954) |
| **Akurasi uji tanpa duplikat (n=445)** | **0,9551** (top-3 0,9933) |
| ECE mentah → terkalibrasi (suhu 0,638) | 0,1018 → 0,0106 (penuh); 0,102 → 0,020 (tanpa duplikat) |
| Audit kebocoran | uji: 114 duplikat persis + 88 hampir-duplikat terhadap train (dHash ≤ 3 bit); train sendiri memuat 461 duplikat persis |
| SHA-256 `model.pt` | `e55cbc98e03f9e386e03b87427061032aa2e9279dd5a1ed9b03a92211b8e96ed` |

Angka yang pantas dilaporkan adalah **0,955 (tanpa duplikat)**, bukan 0,969. **Akurasi pada foto pengguna beOkay nyata tidak diketahui.** Dataset hasil scraping, lisensi tidak tercantum → status model **`RESEARCH_ONLY`**; 13 kelas termasuk pizza/burger/kentang goreng yang kurang relevan; hanya nama hidangan (bukan kalori/porsi).

**Deploy Modal:** app `beokay-dish-classifier` (`ml/modal_app.py`), Volume `beokay-models` (`/dish/v1-20261109/`, `current.json` dengan SHA yang diverifikasi saat memuat), Secret `beokay-ml-auth` (token acak, juga di `.env` yang diabaikan git; tidak pernah dicetak). Diuji pada endpoint nyata:
- tanpa token → 401; token salah → 401; Base64 rusak → 422; bukan gambar → 422;
- valid → 200 dengan `modelVersion`, `artifactSha256` yang cocok, tiga prediksi; **cold start ≈ 9–10 dtk, hangat ≈ 1,3–1,6 dtk total (inferensi 28–72 ms)**;
- klien API (`createModalClient`) di container memanggil endpoint nyata dan lolos validasi respons.

Satu cacat ditemukan dan diperbaiki saat deploy: versi awal membaca `authorization` sebagai parameter query FastAPI (tidak akan pernah menerima header Bearer); sekarang memakai `Header()` lewat `@modal.asgi_app()`.

**Tata kelola:** hanya model `APPROVED` yang boleh memengaruhi hasil pengguna. Model ini `RESEARCH_ONLY`, jadi hanya berjalan **bayangan**, dan hanya untuk pengguna dengan persetujuan `model_inference`.
Terverifikasi di emulator: pemindaian foto 200 dalam ≈ 2 dtk (jalur Mistral), pengguna melihat hasil Mistral ("tidak ada makanan yang terlihat jelas" untuk gambar derau); baris `ml_inference_runs` mode `SHADOW`, status `OK`, 9,3 dtk, 28.085 byte, label teratas dan probabilitas — **tanpa gambar**. Catatan jujur: gambar derau diklasifikasikan "French Fries" 0,59–0,73, bukti bahwa model terlalu percaya diri pada masukan di luar distribusi; alasan tambahan ia tidak boleh dipakai langsung.

## C2. Butir lanjutan (10 November 2026)
Dikerjakan setelah permintaan "kerjakan yang belum dikerjakan" dan izin pemilik menaikkan status model.
| Butir | Yang dibangun | Bukti |
|---|---|---|
| Teks dari LLM (Mistral) | `llm-text.ts`: model hanya **menulis ulang** penjelasan dari fakta yang sudah divalidasi. Keluaran harus lolos gerbang: aman (`FORBIDDEN_CLAIMS`), memuat nama persis, **tanpa angka yang tidak ada di fakta**, tanpa tautan/markup, ≤ 420 karakter; selain itu **templat** dengan alasan fallback. Batas waktu keras 8 dtk. Consent baru `ai_text_generation` (data yang dikirim: nama makanan/aktivitas, nilai gizi bersumber, alasan peringkat, kata pencarian; **tidak** nama/surel/alergi/glukosa). | 6 tes unit (gerbang, timeout, kegagalan, tanpa kunci, tanpa pengenal pengguna); **dijalankan nyata**: 3 dari 3 penjelasan memakai `mistral-small-latest` dan lolos gerbang (≤ 1,4 dtk); tanpa consent/kunci → templat (tes integrasi) |
| Percakapan multi-giliran | `agent_runs.parent_run_id`/`turn` (maks 20). "pilihan lain" menjalankan ulang maksud dan kueri induk **tanpa kandidat yang sudah ditawarkan**; "kenapa" menjelaskan tanpa alat dari alasan peringkat. Run induk milik orang lain → 404. | tes integrasi; **emulator**: giliran 2 tampil di bawah giliran 1 tanpa pengulangan |
| SSE streaming | `POST /runs?async=1` → 202 segera dan eksekusi di latar; `GET /runs/:id/stream` memutar ulang `agent_run_events`, mendukung `Last-Event-ID`, detak jantung, dan berakhir dengan peristiwa `state`; consent dicabut → `BLOCKED` tanpa saran. Flutter: teks kemajuan dari aliran, **jatuh ke polling** bila aliran gagal. | tes integrasi + 2 tes widget; **nyata**: 13 peristiwa berurutan, total ≈ 2,9 dtk termasuk LLM |
| Outbox peristiwa | `outbox_events` ditulis **dalam transaksi yang sama** dengan keputusan/umpan balik/hasil; klaim `FOR UPDATE SKIP LOCKED`, backoff, dead-letter setelah 5 percobaan, `dedupe_key` unik; pekerja dalam proses (3 dtk) + sapuan hasil terukur (60 dtk). Pengiriman minimal-sekali; penangan idempoten. | tes: ditulis bersama keputusan, dedupe, retry→DEAD, tiga pekerja paralel tidak ganda |
| Hasil terukur (MealLog) | `recommendation_outcomes`: rencana diterima dicocokkan dengan **catatan nyata** (butir makan sesudah rencana; sesi aktivitas pada tanggal rencana, jenis sama, durasi ≥ 50%). Berbeda dari umpan balik yang dilaporkan sendiri. Catatan diarsipkan → hasil **ditarik** dan pengaruhnya dibatalkan. | tes integrasi (makan, aktivitas, penarikan, consent); **emulator**: rencana jalan kaki lama menampilkan "Terbukti: sesi sejenis tercatat" |
| Personalisasi v2 | `pref-rules-v2`: bobot "disukai" dari hasil terukur; bonus 0,2 × bobot (< penalti 0,6 agar bukti makan tidak mengalahkan penolakan); alasan ditampilkan. | tes unit + integrasi (peringkat naik dengan alasan, kembali setelah penarikan) |
| Persetujuan model | Kolom `approved_at`/`approval_note` + CHECK: `APPROVED` wajib bercatatan ≥ 20 karakter. Skrip `scripts/ml/set-model-status.ts` menolak `APPROVED` bila akurasi uji tanpa duplikat < 0,90. Model **disetujui di DB dev** atas izin pemilik; catatan memuat risiko yang diketahui. | tes DB (CHECK), skrip diuji (catatan pendek ditolak) |
| Perkiraan model (LIVE) | Hanya model `APPROVED` + consent `model_inference`; ditampilkan sebagai **perkiraan terpisah** (bukan item, bukan catatan), hanya bila keyakinan terkalibrasi ≥ 0,85; Modal gagal/lambat (> 4 dtk) → hasil utama tetap tampil tanpa perkiraan. Pemanasan `POST /api/me/ml/warmup` saat pengguna memilih "Foto makanan". | tes integrasi (assist, ambang, kegagalan, audit LIVE tanpa gambar, warm-up); **nyata**: foto nasi goreng → "Nasi Goreng" 0,983 sesuai bacaan Mistral; **emulator**: kartu "Perkiraan model (masih diuji)" |
| Pemulihan setelah restart | `GET /api/me/agent/pending`; layar Asisten memuat saran yang menunggu saat dibuka. | tes server + 2 tes widget; **emulator**: mulai ulang aplikasi → saran tampil lagi |

Cacat yang ditemukan dan diperbaiki saat pekerjaan ini: (a) layar Asisten tidak memulihkan saran setelah restart (E2E-11) → endpoint pemulihan; (b) cold start Modal (≈ 11 dtk) membuat perkiraan hampir tak pernah tampil → pemanasan; (c) timeout `fetch` tiruan tidak menghormati `AbortSignal` → batas waktu keras dengan `Promise.race`.

## D. Personalisasi
Penolakan → bobot kata nama makanan (maks 5) → penalti 0,6 × bobot; makanan yang **terukur dimakan** → bonus 0,2 × bobot (v2); versi profil naik + peristiwa; pengguna dapat menghapus. **Bukan pembelajaran mesin.** Belum ada: preferensi waktu, personalisasi untuk aktivitas.

## E. Komunitas — keputusan privasi
Lihat arsitektur. Ringkas: tidak ada data kesehatan yang keluar dari pengguna; yang terlihat hanya alias, skor, peringkat; papan peringkat ditekan di bawah 5 peserta yang bersedia tampil; keluar/tarik persetujuan berlaku langsung; skema tanpa FK ke tabel kesehatan. Skor tidak memberi poin untuk intensitas atau nilai kesehatan; hari tanpa catatan tidak mengurangi skor.

## F. Pengujian (Docker, DB uji terisolasi)
- Backend: `tsc` bersih; **219 tes lulus** pada proses API yang baru (1588 expect, 46 berkas). Catatan: menjalankan rangkaian berulang kali terhadap **proses API yang sama** kadang menggagalkan satu tes acak (`identity`/`trends`; terlihat 2 dari 4 putaran), sedangkan pada API yang dibuat ulang selalu lulus; dugaan saya pembatas laju autentikasi yang menumpuk, **tidak diverifikasi**.
- Flutter: `analyze` **0 temuan**; **151 tes lulus** (Asisten 12, komunitas/tantangan 5, pindai foto 7 termasuk perkiraan model).
- Drift Prisma: `gen_random_uuid` tabel auth, indeks HNSW, **dan tiga objek khusus-SQL yang tidak terwakili di skema Prisma** (FK `activity_plans.linked_session_id`, FK `score_events.reversal_of`, indeks unik `communities_region_code_name_key`). Ketiganya sengaja berasal dari migrasi tangan dan tidak berbahaya, tetapi **tidak saya laporkan pada laporan sebelumnya yang menyebut drift hanya noise**; koreksi tercatat di sini.
- **Emulator Pixel_4 (Android, Appium MCP):** layar Asisten (permintaan aktivitas → dua opsi bersumber dengan batasan → simpan → rencana → selesai), gerbang persetujuan (ditolak tanpa izin, kartu menuju persetujuan, aktif setelah diberikan), komunitas (alias berisi surel ditolak, alias valid diterima, bertahan setelah restart aplikasi), tantangan (ikut, skor, check-in, saklar papan peringkat ditolak tanpa persetujuan), foto makanan + inferensi bayangan.

Temuan dari uji emulator dan perbaikannya:
1. Dialog alias memakai `TextEditingController` yang di-dispose sebelum animasi tutup selesai → diganti widget dialog berstate (uji widget mereproduksi).
2. Rute `/challenge/:id` crash (`type 'Null' is not a subtype of type 'Challenge'`) setelah kembali dari layar persetujuan → ditambah `redirect` ke daftar komunitas bila `extra` hilang. **Akar penyebab hilangnya `extra` tidak saya temukan**; yang ada hanya penjaga.
3. Pesan 403 persetujuan tantangan generik → kartu "Persetujuan diperlukan" dengan tombol ke Persetujuan data.
4. Subtitle Profil "Cari alternatif makanan" usang → diperbarui.
5. **Tidak terjelaskan:** sekali, setelah check-in, mengetuk saklar papan peringkat menampilkan "Tidak bisa terhubung" padahal tidak ada permintaan di log API; ketukan ulang berjalan normal (403 persetujuan). Saya anggap gangguan sesaat adb reverse, tetapi **tidak terbukti**.
- **Regresi Pengingat di emulator (10 Nov):** layar memuat, pengingat glukosa dibuat → tersimpan di server → alarm lokal terjadwal (`dumpsys alarm`), dinonaktifkan → server `enabled=false`. Pembatalan alarm per-pengingat tidak diverifikasi terpisah.
- **Matriks E2E-01…12:** `docs/testing/p2-e2e-matrix.md` (E2E-05 dibuktikan dengan restart proses API sungguhan).
- **Tidak dijalankan:** push FCM nyata (terblokir Firebase), uji penetrasi terpisah, uji beban.

## G. Dokumen
`docs/audits/p2-continuation-audit.md`, `docs/architecture/p2-agent-and-personalization.md`, `docs/testing/p2-e2e-matrix.md`, `docs/reports/p2-execution-plan.md`, laporan ini. Artefak ML: `ml/kaggle/{train.py,kernel-metadata.json}`, `ml/modal_app.py`.

## H. Risiko dan celah yang belum terselesaikan
1. **Belum dibangun dari master prompt:** alat konteks glukosa/ringkasan mingguan/kalkulator/korpus bukti terkurasi untuk agen; metrik observabilitas agregat dan korelasi trace ke Flutter; dokumen tinjauan keamanan formal; "Weekly Review" otomatis pada E2E-12.
2. **Model `dish-classifier` berstatus `APPROVED` di DB dev atas izin pemilik, dengan risiko yang diketahui:** lisensi dataset tidak tercantum; akurasi 0,955 (tanpa duplikat) diukur pada data uji dari sumber yang sama, **bukan foto pengguna beOkay**; model terlalu percaya diri pada masukan di luar distribusi (derau → "French Fries" 0,59–0,73; di bawah ambang 0,85, tetapi ambang bukan jaminan). Mitigasi yang ada: hanya perkiraan terpisah, berlabel uji, ≥ 0,85, tidak pernah dicatat otomatis, dapat dimatikan pengguna (consent) dan dibatalkan pemilik (`DEPRECATED`). **Produksi belum disetujui**: baris registri dan persetujuan harus dibuat sendiri di produksi.
3. **Persetujuan model di dev hanya lewat skrip sekali jalan**; tidak ada UI/alur peninjauan formal.
4. Modal berskala-ke-nol: cold start ≈ 9–11 dtk; pemanasan hanya membantu bila pengguna memilih foto beberapa detik sebelum mengirim. Biaya Modal/Mistral ada di akun pemilik. Tidak ada rotasi token otomatis.
5. **Teks LLM dikirim ke pihak ketiga (Mistral)** hanya dengan consent `ai_text_generation`; gerbang deterministik mencegah angka/klaim baru tetapi **tidak menjamin gaya yang tepat**. Tidak ada evaluasi juri LLM atau klinisi.
6. **Kebijakan keselamatan berbasis regex** (ID/EN), belum ditinjau klinisi. Pengecekan alergi hanya dari nama makanan.
7. **Enam consent baru ditambahkan tanpa menaikkan versi kebijakan**, dan deskripsi `model_inference` diubah (kini menyebut hasil dapat tampil setelah model disetujui); perlu tinjauan pemilik/hukum. Ambang kohort 5 adalah pilihan saya, bukan standar hukum.
8. **Hasil terukur memakai pencocokan nama yang heuristik** (semua kata bermakna bila nama ≤ 2 kata, minimal dua bila lebih): dapat salah cocok/terlewat; bonus kecil dan dapat dihapus pengguna, tetapi tidak sempurna.
9. Outbox: pengiriman minimal-sekali, penangan hanya internal (tidak ada konsumen eksternal); pekerja berjalan dalam proses API (bukan layanan terpisah).
10. UI tanpa desain FigCraft (MCP tidak pernah tersambung; keputusan pemilik tercatat). `applicationId` masih `com.example.app`; push FCM terblokir sampai aplikasi didaftarkan di Firebase.
11. Batas laju agen dalam memori per proses; skor/kohort dihitung saat baca dan disapu berkala.
12. Dua galat UI yang tidak terjelaskan akarnya (hilangnya `extra` pada rute tantangan, "Tidak bisa terhubung" sesaat); keduanya hanya terjaga/terpantau.
13. P1 yang masih terbuka (lihat laporan P0/P1) tetap berlaku.

## I. Langkah berikutnya yang disarankan
1. Keputusan pemilik: lisensi dataset dan apakah persetujuan model berlaku di produksi; tinjauan hukum atas consent dan ambang kohort.
2. Kumpulkan evaluasi pada foto pengguna nyata (dengan consent) sebelum menaikkan ambang atau memperluas kelas.
3. Hubungkan agen ke ringkasan mingguan/tujuan (E2E-12 penuh) dan tinjauan klinisi atas kebijakan keselamatan.
4. Daftarkan aplikasi di Firebase (applicationId asli) untuk push nyata.
5. Selidiki akar galat UI tak terjelaskan dan pembatas laju yang diduga menyebabkan tes acak gagal.
