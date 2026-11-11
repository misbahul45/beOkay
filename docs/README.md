# Dokumentasi beOkay

beOkay adalah platform pencatatan kebiasaan harian untuk orang dewasa dengan diabetes tipe 2: aplikasi Android (Flutter) + API modular (Bun/TypeScript) + PostgreSQL (pgvector). Dokumentasi ini disusun dari audit kode **10 November 2026**.

## Mulai dari sini

| Kebutuhan | Dokumen |
|---|---|
| Memahami sistem secara utuh (komponen, alur, invarian, keselamatan, privasi) | [architecture/system-overview.md](architecture/system-overview.md) |
| Mencari tahu modul server tertentu (tabel, consent, aturan, tes) | [reference/server-modules.md](reference/server-modules.md) |
| Daftar semua tabel, constraint, dan migrasi | [database/schema-reference.md](database/schema-reference.md) |
| Daftar semua endpoint, consent, dan kode galat | [api/endpoint-reference.md](api/endpoint-reference.md) |
| Aplikasi Flutter (struktur, rute, offline, Android) | [architecture/mobile-app.md](architecture/mobile-app.md) |
| Menjalankan, menguji, memigrasi, merilis; variabel lingkungan; pipeline TKPI & model | [operations/runbook.md](operations/runbook.md) |
| Kondisi proyek, risiko, dan apa yang harus dibereskan | [audits/full-project-audit-2026-11-10.md](audits/full-project-audit-2026-11-10.md) |
| beOkay 3.0: audit Fase 0, sistem desain & navigasi (Fase 1), Beranda & statistik (Fase 2), rencana fase berikutnya | [reports/beokay-3.0-phase-0-2.md](reports/beokay-3.0-phase-0-2.md) |
| beOkay 3.0 Fase 3: Asisten percakapan (router, bagian bertipe, gerbang identitas makanan) | [reports/beokay-3.0-phase-3.md](reports/beokay-3.0-phase-3.md) |

## Status singkat (per 10 November 2026)

| Tahap | Cakupan | Status menurut laporan proyek | Catatan audit |
|---|---|---|---|
| P0 | identitas, consent, onboarding, profil; makan, glukosa, aktivitas, obat, tujuan, linimasa, sinkronisasi offline, ringkasan | selesai | terverifikasi lewat tes otomatis |
| P1 | kalkulator porsi, pencarian makanan (lokal + OFF/USDA + TKPI), barcode, pemindaian label/foto, preferensi & alergi, pengingat, push, ekspor, impor Health Connect, insight kontekstual, tren | selesai, dengan keterbatasan | UI dibangun tanpa desain FigCraft; push nyata terblokir Firebase |
| P2 | agen nutrisi + aktivitas (persetujuan tepat-sekali), personalisasi deterministik, komunitas/tantangan/skor, registri model + Modal, teks saran Mistral, SSE, outbox, hasil terukur | `P2_FUNCTIONALLY_COMPLETE_WITH_LIMITATIONS` | siklus tantangan tidak ada (F-04); registri model tanpa alat (F-16) |
| P3 | mesin intervensi JITAI (tahap awal), pembersihan UX | irisan vertikal; 5 dari 13 kapabilitas `NOT_STARTED` (P3-04, 06, 08, 11, 13) | lihat [reports/p3-execution-plan.md](reports/p3-execution-plan.md) |
| 3.0 | sistem desain v3, beOkay Spark, navigasi Asisten, mesin statistik `stats-v1`, Beranda adaptif, Asisten percakapan | Fase 0–3 selesai; Fase 4–7 direncanakan | [phase-0-2](reports/beokay-3.0-phase-0-2.md) · [phase-3](reports/beokay-3.0-phase-3.md) |

Verifikasi terakhir (setelah 3.0 Fase 3): `tsc` bersih · backend **270/270** tes · `flutter analyze` bersih · Flutter **179/179** tes. Pemblokir rilis F-01 (hapus akun) dan F-02 (ekspor lengkap) sudah ditutup; F-03 tinggal kunci rilis pemilik dan pendaftaran Firebase; F-10 ditutup. Mode gelap mengikuti sistem.

## Peta dokumen lama

Dokumen di bawah ini dibuat per tahap (P0–P3) sebagai catatan kerja dan bukti. Isinya berguna sebagai riwayat dan jejak keputusan, tetapi **angka tes dan pernyataan "belum ada" di dalamnya adalah potret waktu itu**. Bila bertentangan dengan dokumen baru, ikuti kode, lalu dokumen baru.

| Folder | Isi | Catatan |
|---|---|---|
| `architecture/` | per domain (`activity`, `glucose`, `nutrition`, `core-health-experience`, `auth-personalization`), kontrak integrasi P0, agen & personalisasi P2, peta dependensi P2/P3, push | `p2-agent-and-personalization.md` dan `push-notifications.md` masih akurat sebagai penjelasan desain |
| `audits/` | audit kesiapan per tahap (`auth-personalization`, `core-health-experience`, `p1`, `p2`, `p2-continuation`, `p3`) | `p3-readiness-audit.md` memuat daftar celah G-01…G-06 |
| `database/` | skema per domain | digantikan oleh [schema-reference](database/schema-reference.md) |
| `api/` | `README.md`, `activity.md`, `glucose.md`, `nutrition.md`, koleksi `bruno/` | contoh payload tiga domain; sisanya di [endpoint-reference](api/endpoint-reference.md) |
| `design/` | spesifikasi FigCraft & riset UI (P0) | berkas desain FigCraft sendiri tidak ada di repo |
| `reports/` | rencana & laporan implementasi per tahap | `p2-completion-report.md` memuat bukti pelatihan Kaggle dan deploy Modal |
| `research/` | `trend-charts.md` | dasar desain grafik tren |
| `testing/` | matriks & hasil uji (termasuk Appium, E2E P2) | `p2-e2e-matrix.md` |
| `repomix-output.xml` | paket otomatis seluruh kode | basi; kandidat dihapus (F-07) |

Di luar `docs/`: `AGENTS.md` / `CLAUDE.md` (aturan kerja agen — sebagian usang, F-08), `ide.md` (blueprint produk 3.0: spesifikasi **target**, bukan status).

## Aturan kerja penting (dari `AGENTS.md`)

1. Perintah server dijalankan **di Docker**, bukan di host; Flutter di host.
2. Tidak ada `git commit/push` oleh agen; pengguna yang meng-commit.
3. Tidak ada rahasia sebagai literal di berkas ter-track; skrip sementara jangan di dalam repo.
4. Query selalu dibatasi `user_id` dari sesi; endpoint data kesehatan wajib `consentService.requireConsent`.
5. Nilai tidak diketahui = `NULL`; prediksi tidak disimpan di tabel pengukuran; koreksi lewat `record_revisions`.
6. Desain UI dikerjakan di Figma (FigCraft) sebelum implementasi — MCP `figcraft` saat ini gagal tersambung.
