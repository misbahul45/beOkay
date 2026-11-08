# Core Health — laporan implementasi Slice 1

Pembaruan Slice 3: [laporan Glucose](glucose-implementation.md) mencatat tracking manual online, unit asli/kanonik, revisi/koreksi, archive/restore, grafik titik, Today dan timeline meal+glucose. Ini bukan penyelesaian seluruh P0/P1. Implementasi berhenti untuk review sebelum Activity.

Pembaruan Slice 2: [laporan Nutrition](nutrition-implementation.md) mencatat fitur meal online dan integrasinya. Status belum tersedia pada tabel Slice 1 di bawah merupakan catatan tahap sebelumnya; bukan status Nutrition terbaru. Keseluruhan P0/P1 belum selesai.

Pembaruan verifikasi 8 November 2026: **Appium Today telah dijalankan**, 13 skenario terverifikasi pada emulator Android dengan API/PostgreSQL nyata: login, timezone/date, unit, refresh, restart, network retry, consent, pergantian akun dan sesi dicabut. [Laporan dan screenshot](../testing/today-appium.md). Pernyataan belum ada Appium di bagian verifikasi awal di bawah adalah status sebelum pengujian lanjutan ini. P0/P1 tetap belum lengkap.

Tanggal: 8 November 2026. Milestone: **Today Foundation siap direview**. Pengerjaan berhenti sebelum Nutrition sesuai permintaan pengguna. FEAT-01 penuh dan keseluruhan P0 belum selesai.

## A. Audit fondasi

Flutter sudah memiliki auth, onboarding, consent, profile, health profile, preferences, Riverpod, go_router, secure token storage, tema Inter dan komponen bersama. Backend memakai Bun, Prisma 7, PostgreSQL dan Better Auth. Pernyataan scaffold Flutter pada AGENTS.md tertinggal dari sumber aktual. Tidak ada modul/tabel tracking atau koleksi Bruno sebelum pekerjaan ini.

Audit terperinci beserta prioritas, bukti dan rencana per slice: [core-health-experience-audit.md](../audits/core-health-experience-audit.md). Auth/onboarding existing dipertahankan; tidak ada mekanisme autentikasi baru.

## B. Implementasi dan status

| Bagian | Hasil aktual |
|---|---|
| Today API | Endpoint baru, metadata akun nyata dari profil/preferensi, date/greeting sesuai IANA timezone |
| Keamanan Today | Better Auth verified session, kedua purpose consent current, identitas dari sesi, no-store |
| Today Flutter | Charcoal editorial card, empat preview domain berlabel belum tersedia, profil, loading/error/consent/retry |
| Lifecycle | Provider autoDispose mengikuti auth, consent, profil dan preferensi; refresh setiap menit, saat app resume, dan manual |
| Metrik tracking | Belum tersedia; null dan NOT_IMPLEMENTED, tanpa pengukuran atau progress rekaan |
| Quick Record dan navigation empat tab | Belum dibuat; dua tab existing dipertahankan sampai destination tersedia |
| FEAT-02 sampai FEAT-11 | Belum diimplementasikan; guard consent existing dipakai untuk Today |
| P1 | Belum diimplementasikan |

Nama ditampilkan dari state auth existing; tanggal, greeting dan preferensi Today melalui API. Model Flutter saat ini membaca metadata Today, bukan metrik domain; perlu diperluas bersama slice Nutrition. Tidak ada klaim dashboard tracking lengkap.

## C. Database

Tidak ada migrasi atau tabel baru. Today memakai sumber identitas/profil/preferensi/consent existing melalui service masing-masing. Tidak menyentuh skema auth generated. [Status skema](../database/health-tracking-schema.md).

## D. Kontrak API

`GET /api/me/today`, tanpa body dan tanpa parameter identitas. Respons mencakup date, timezone, greeting, displayName, glucoseUnit, generatedAt, computationVersion, analyticsState dan availability domain. Respons 401 tanpa sesi valid; 403 bila salah satu consent wajib tidak aktif. [Kontrak lengkap dan contoh sintetis](../api/README.md).

## E. Desain

Arsip FigCraft existing dibaca: format `figcraft` v1, empat halaman `00 Cover & Brief`, `01 Design System`, `02 Screens`, `03 States`; imageIndex kosong. Thumbnail cover diperiksa. MCP FigCraft tidak tersedia: tidak ada editable source baru, page 09–19 baru, approval desain atau verifikasi parity FigCraft yang diklaim.

Fallback yang diizinkan prompt ada di [spesifikasi desain](../design/core-health-figcraft-spec.md). Tema dan token existing dipakai; tidak ada foto baru. Screenshot Flutter dengan font Inter dan ikon asli diperiksa di `/tmp/beokay-today-review/today-foundation.png`: greeting, tanggal/zona waktu, charcoal card, ringkasan dan navigasi terbaca pada viewport 390×844. Konten bawah dapat di-scroll. Pemeriksaan ini hanya viewport awal; tidak membuktikan audit visual seluruh layar/perangkat.

## F. Flutter

`app/lib/features/today/` memisahkan data, application dan presentation. Home existing menyertakan TodaySection dan akses profil. ApiClient dan secure bearer storage existing tetap dipakai. Error/reload tidak menampilkan AsyncValue lama. Tidak ada database health lokal, dukungan offline recording, atau sync pada milestone ini.

## G. Hasil tes aktual

| Perintah / pemeriksaan | Hasil |
|---|---|
| Red backend sebelum implementasi | Gagal: Today 404 vs 401 dan modul today.model belum ada |
| Red widget sebelum implementasi | Gagal kompilasi: tiga file Today belum ada |
| `docker compose -f compose.test.yaml run --rm tester bun test` | **3 pass, 0 fail; 51 expect calls**, dua berkas |
| `docker compose -f compose.test.yaml exec -T api-test bun run typecheck` | **Lulus** |
| `flutter test` | **26 pass**, termasuk regresi auth/onboarding dan dua tes Today |
| `flutter analyze` | **No issues found** |
| `flutter build apk --debug --no-pub` | **Lulus**, `app/build/app/outputs/flutter-apk/app-debug.apk` |
| Bruno collection pada API uji | **3 requests pass, 3/3 tests pass**; CLI menampilkan assertions 0/0 karena pemeriksaan berada dalam blok tests |
| Screenshot dengan font Inter | Render dan inspeksi visual dilakukan |
| `git diff --check` | **Lulus** pada perubahan yang diperiksa |

Unit backend menguji midnight pada Asia/Jakarta, offset negatif Los Angeles, greeting lokal, unit preference, null metrics dan analytics NOT_AVAILABLE. Integrasi memakai API, PostgreSQL dan Mailpit terisolasi: registrasi, verifikasi, login, onboarding, metadata Today, dua akun berbeda, query userId tidak mengganti identitas, withdrawal health/summary consent, logout dan penolakan sesi lama. Tidak ada pengukuran health sintetis yang ditampilkan sebagai data pengguna.

Widget Today menguji lebar 320 px, text scale 2, tidak ada nilai nol rekaan, error jaringan dan retry. Regresi identity menggunakan FakeBackend; hasilnya bukan E2E perangkat nyata. APK baru berhasil dibangun, tetapi belum ada pengujian Appium/E2E perangkat untuk Today pada sesi ini. Pending-response saat account switch belum memiliki tes provider terpisah.

## H. Bruno

Satu collection baru pada `docs/api/bruno`, karena koleksi existing tidak ditemukan. Environment `test` hanya menyimpan baseUrl. Folder Today dan Security berisi request 200, 401, 403 beserta executable tests. Semua request dijalankan dalam container Node sementara dengan Bruno CLI, terhadap akun sintetis verified. Bootstrap fixture ada di `/tmp`; password dibangkitkan saat runtime dan token tidak ditulis ke repository. [Instruksi tes](../testing/core-health-experience.md).

## I. Keamanan, privasi dan batas klinis

Sesi dan kedua consent diverifikasi oleh server. Dua akun dengan preferensi berbeda menerima konteks sendiri. Client userId di query tidak dipakai sebagai otorisasi. Tidak ada perubahan aturan password/auth atau dependensi aplikasi. Tidak ada diagnosis, target glukosa, saran dosis, klaim kausal atau estimasi medis. Preview tidak menyatakan jadwal obat sebagai konsumsi aktual. Retensi, offline health storage dan sync masih perlu implementasi serta verifikasi pada slice terkait. Kebijakan consent existing masih draf dan belum mendapat tinjauan legal.

## J. Risiko dan keterbatasan

Today Foundation belum mengagregasi catatan: seluruh domain tracking belum ada. NOT_IMPLEMENTED berbeda dari histori kosong yang sudah diperiksa. Timer refresh satu menit berarti pergantian tanggal pada layar aktif dapat tertunda sampai sekitar satu menit; app resume dan tombol reload mengambil konteks baru. Tidak ada cache kesehatan offline. Desain editable FigCraft dan validasi visual lintas perangkat belum tersedia. Laporan ini tidak menyatakan production readiness keseluruhan aplikasi.

## K. Acceptance dan checkpoint

**Selesai pada milestone ini:** audit awal, spesifikasi fallback, kontrak dan endpoint Today Foundation, UI foundation, tes terkait, Bruno dan dokumentasi. **Belum selesai:** FEAT-01 lengkap, FEAT-02–11 dan semua P1. Seluruh checkbox Definition of Done P0 tidak dapat ditandai selesai.

Next action: pengguna mereview kode Today Foundation. Setelah pengguna meminta lanjut ke fitur berikutnya, kerjakan Slice 2 Nutrition beserta desain, skema/constraint, API, form, histori, integrasi Today/timeline yang relevan, tes dan Bruno; berhenti kembali sesudah slice tersebut. Tidak menjalankan git add/commit/push.
