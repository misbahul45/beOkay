# P2 — audit kesiapan (9 November 2026)

Dokumen ini hanya mencatat apa yang **ada di repositori dan teruji**. Tidak ada klaim kemampuan P2 yang sudah berjalan.

## 1. Baseline terukur (dijalankan pada sesi ini)

| Pemeriksaan | Perintah | Hasil |
|---|---|---|
| Backend: tes unit + integrasi | `docker compose -f compose.test.yaml run --rm tester bun test` (DB uji terisolasi) | **69 lulus, 0 gagal**, 588 expect, 21 berkas |
| Backend: typecheck | `... tester bun run typecheck` | bersih (tanpa galat) |
| Flutter: analisis statis | `flutter analyze` (host, sesuai pengecualian AGENTS.md) | tanpa masalah |
| Flutter: tes | `flutter test` | **97 lulus** |

Catatan: working tree berisi perubahan belum di-commit milik pengguna (grafik tren: `day_chart.dart`, `trends.dart`, `trend_charts.dart`, `trends_screen.dart`, `trends_test.dart`, laporan status). Perubahan itu tidak disentuh.

## 2. Klasifikasi dependensi P2

Status: `VERIFIED` · `IMPLEMENTED_NOT_VERIFIED` · `INCOMPLETE` · `MISSING` · `BLOCKED`.

| Kemampuan | Status | Bukti / celah | Dampak ke P2 |
|---|---|---|---|
| Better Auth (sesi, bearer, verifikasi email) | VERIFIED | `features/auth`, `tests/integration/identity.test.ts`; guard `authenticated()` di `features/auth/guard.ts` | Identitas run agen berasal dari sesi server |
| Consent | **INCOMPLETE untuk P2** | Hanya 3 tujuan: `health_data_processing`, `descriptive_summaries`, `product_analytics` (`consent.policy.ts`, versi 1.0). `requireConsent(userId, purpose)` sudah dipakai di layanan domain | Perlu tujuan baru berversi (lihat §4). Tanpa itu **tidak boleh** memanggil LLM/Modal dengan data kesehatan |
| Nutrition (log makan, snapshot nutrien) | VERIFIED | `features/nutrition`, `tests/integration/nutrition.test.ts`, `food-calc.test.ts` | Dipakai alat `get_nutrition_summary`, `calculate_nutrition` |
| Food Discovery (lokal-dahulu, Open Food Facts, USDA, barcode) | VERIFIED (fixture); USDA nonaktif tanpa kunci | `features/food-discovery`; OFF belum diuji ke jaringan nyata untuk pencarian teks | Dipakai ulang oleh alat `search_food_catalog`/`discover_food_candidates` |
| Food Vision (OCR label, nama dari foto) | VERIFIED (emulator, Mistral nyata) | `features/food-vision` | Opsional; tidak diperlukan P2 inti |
| Glukosa | VERIFIED | `features/glucose`, tes | Ringkasan deskriptif saja; tidak ada prediksi |
| Aktivitas manual | VERIFIED | `ActivitySession.source` + `qualityStatus` | Sumber `manual` ada; kolom sudah siap menampung sumber impor |
| **Impor wearable / Health Connect** | **MISSING** | Tidak ada kode server maupun Flutter (grep `wearable`/`health_connect` kosong; tidak ada plugin di `pubspec.yaml`) | Metrik wearable **tidak boleh** dikarang. Fitur aktivitas P2 berjalan hanya dari catatan manual dengan status `wearable: UNAVAILABLE` |
| Obat (regimen, jadwal, konfirmasi) | VERIFIED online | `features/medication` | Hanya sebagai konteks keselamatan; **dilarang** saran dosis. Dikirim ke LLM hanya bila perlu dan dengan consent |
| Tujuan perilaku (goal, check-in, progres turunan) | VERIFIED online | `features/goals`, `BehaviorGoal`, `GoalCheckin` | Dasar tantangan dan mikro-aksi; tujuan pengguna tetap otoritatif |
| Timeline | VERIFIED | `features/timeline` | — |
| Insight deskriptif (harian, mingguan, tren) | VERIFIED | `features/insights`, `summary_projections` | Dasar Workflow C (coaching mingguan); "insight kontekstual" P1 **belum ada** |
| Offline sync | VERIFIED untuk pembuatan baru | `/api/me/sync/operations`; koreksi tidak diantrekan | Aksi P2 (konfirmasi rencana) boleh mensyaratkan koneksi |
| **Preferensi makanan, alergi, pembatasan** | **MISSING** | Tidak ada model/kolom/endpoint. `UserSettings` hanya locale, timezone, unit glukosa, ukuran teks | **Penghalang keras** untuk P2-06 (filter kendala keras alergi). Harus dibuat lebih dulu |
| **Rencana makan tersimpan (planned meal)** | **MISSING** | `MealLog` adalah makanan yang dikonsumsi; belum ada entitas rencana | P2 membutuhkan pemisahan "rencana" vs "dikonsumsi" |
| **Reminder engine** | **MISSING** | Tidak ada kode (grep `reminder`/`pengingat` kosong) | Konfirmasi pengingat di Workflow tidak bisa dijanjikan; ditandai nonaktif |
| **Ekspor data** | **MISSING** | Tidak ada endpoint | Diperlukan untuk kebijakan privasi/penghapusan; masuk daftar celah |
| Penghapusan akun / tarik consent lintas komponen | PARTIAL | Tarik consent → 403 dan antrean klien dibersihkan (VERIFIED); belum ada jalur penghapusan untuk checkpoint agen, cache, komunitas (belum ada) | Harus dirancang bersama tabel P2 |
| Rate limit | PARTIAL | Rate limit Better Auth; pembatas per pengguna kecil di `food-discovery`/`food-vision` (dalam memori) | Perlu pembatas bersama untuk gateway agen |
| Redis / antrean / worker | **MISSING** | `infrastructure/cache`, `queue`, `llm`, `observability` adalah direktori kosong; tidak ada Redis di compose | Tidak diperkenalkan dulu (lihat rencana: outbox di Postgres) |
| Python / FastAPI / LangGraph | **MISSING** | Tidak ada folder `ai/`, tidak ada Python di compose | Service baru; berjalan di Docker |
| Modal | **BLOCKED (kredensial/biaya)** | Belum ada kredensial Modal di `.env`; tidak ada persetujuan biaya | Klien + kontrak + tes lokal dikerjakan; deploy staging dilaporkan *unverified* sampai pengguna menyetujui |
| LLM provider untuk agen | IMPLEMENTED_NOT_VERIFIED | `LLM_*` ada di `.env` lokal (izin pengguna, `credentials-sources`), `.env.example` memuat nama variabel; belum ada kode pemanggil | Dipakai oleh service Python; nilai tidak dicetak |
| Embedding / RAG | INCOMPLETE | `MISTRAL_EMBEDDING_MODEL=mistral-embed` terverifikasi HTTP 200; pgvector ada di image tetapi **ekstensi belum dibuat**; **belum ada korpus bukti yang disetujui** (PDF gizi tidak diingest: hasil pindai 72 ppi) | Evidence retrieval tidak boleh mengutip sumber yang belum ditinjau |
| Data latih model ML | **MISSING** | Tidak ada dataset, label, atau jejak pelatihan | Tidak ada model yang boleh berstatus `APPROVED` |
| Desain UI (FigCraft) | **BLOCKED** | MCP `figcraft` gagal terhubung (`CONNECTION_CLOSED`) pada sesi ini; folder `design/` dihapus dari repo | UI Flutter P2 tidak boleh ditulis sebelum desain; CLAUDE.md melarang pengganti mockup tanpa persetujuan |
| Tema gelap | MISSING (sudah tercatat P1) | — | Bukan syarat P2 |

## 3. Dampak pada irisan P2

| Irisan | Dapat dimulai? | Alasan |
|---|---|---|
| P2-00 audit & kontrak | Ya | Dokumen ini |
| P2-01 gateway + service Python | Ya | Hanya butuh sesi, consent, Docker |
| P2-02 konteks pribadi + registri alat | Ya, dengan cakupan data yang ada | Wearable/preferensi makanan dilaporkan `UNAVAILABLE` |
| P2-03 LangGraph | Ya | Butuh checkpoint di Postgres |
| P2-04 bukti & keselamatan | Keselamatan deterministik: ya. **Bukti/RAG: terbatas** | Korpus yang ditinjau belum ada; sebelum itu jawaban tidak boleh berklaim berbukti |
| P2-05 Modal | Klien/registri/fallback: ya. **Deploy: terblokir** | Kredensial + biaya |
| P2-06 nutrisi | **Setelah** preferensi/alergi + rencana makan dibuat (dependensi P1 minimal) | Lihat §2 |
| P2-07 aktivitas | Ya (manual saja) | Wearable tidak ada |
| P2-08 coaching | Ya (tanpa pengingat) | Reminder tidak ada |
| P2-09/10 komunitas, tantangan | Backend ya | Kebijakan kohort minimum perlu peninjauan pemilik produk |
| P2-11 Flutter | **Terblokir sampai FigCraft tersambung** | Aturan proyek |
| P2-12 verifikasi | Backend/Python: ya. E2E perangkat: butuh emulator/Appium | — |

## 4. Keputusan desain yang diusulkan (belum diterapkan)

1. **Consent**: tambah tujuan berversi `personalized_ai`, `external_ai_processing` (LLM pihak ketiga), `model_inference` (Modal), `behavioral_feedback`, `community_membership`, `community_profile_visibility`, `challenge_participation`, `leaderboard_visibility`. Semua opsional dan *off* secara bawaan; versi kebijakan naik ke 1.1. `research_model_training` **tidak ditambahkan** (tidak ada pelatihan dari data pengguna).
2. **Transport agen**: Bun tetap satu-satunya pintu publik. Service Python hanya menerima panggilan dari Bun (token layanan HMAC/bearer rahasia, jaringan Docker internal), dan memanggil balik Bun lewat API konteks internal terbatas — tidak punya kredensial DB.
3. **Persistensi**: Postgres yang sama; checkpoint LangGraph disimpan minimal, dikunci per run/akun, dihapus saat tarik consent/hapus akun. Tanpa Redis pada tahap ini (tidak ada kebutuhan terbukti).
4. **Kebijakan Prisma**: migrasi baru saja; migrasi lama tidak diubah. CHECK dan indeks parsial lewat SQL migrasi sesuai AGENTS.md.

## 5. Celah yang akan dilaporkan sampai ditutup

- Tidak ada impor wearable; tidak ada pengingat; tidak ada ekspor data.
- Tidak ada korpus bukti yang ditinjau; tidak ada dataset/model ML tervalidasi.
- Modal belum bisa dideploy (kredensial, biaya).
- FigCraft tidak tersambung → UI P2 belum bisa dirancang.
- Peninjauan klinis dan hukum (teks consent, kebijakan kohort komunitas, penyedia LLM) di luar kemampuan teknis tim ini.
