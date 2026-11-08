# Nutrition — engineering report Slice 2

Status: VERIFIED untuk slice Nutrition online. Berhenti untuk review pengguna sebelum Glucose. Seluruh P0/P1 belum selesai.

Plan: (1) native FigCraft design/handoff; (2) red tests; (3) Prisma schema/migration with CHECK constraints; (4) authenticated, consent/owner-scoped catalog and meal APIs, immutable nutrition snapshots, optimistic corrections/revisions, archive; (5) Flutter form/history/detail and Today integration; (6) meal timeline and uncached daily read model; (7) unit/integration/widget/Bruno/build verification; (8) final report.

Dependencies follow that order. No further approval needed for local reversible work. No git add/commit/push. Rollback: review diff and revert only this slice's changes; migrations run only on disposable test DB. Existing working tree was clean before implementation.

FigCraft desktop attach completed handshake but document requests timed out because the window was not drawing. Native headless FigCraft CLI uses the same command engine; editable source and rendered preview will be verified before UI implementation. No design approval on behalf of the user is claimed.

Data decisions: no invented nutrient values or seed catalog. Users may add a personal food with source/estimate labels and nullable per-100g nutrients; free-text meal items remain unknown unless defensible grams and nutrients exist. Historical item snapshots survive catalog updates and quantity corrections. Meals archive rather than hard-delete. Corrections require expected version and reason; previous state is retained transactionally. Daily/Today values are computed from current source rows on read, avoiding stale persistent projections in this slice. Full cross-domain summaries/offline sync remain later slices.

## Implementasi yang dapat direview

Sudah tersambung: Today → shared Quick Record (food) → multi-item meal form → PostgreSQL → histori/detail → koreksi/revisions → archive/restore → daily Nutrition read model dan Today. Personal food catalog dapat dibuat/dicari/dipilih; update katalog tersedia lewat API dan tidak mengubah snapshot historis. Unknown nutrients tidak diisi nol; partial totals memiliki coverage. UI menunjukkan source/estimate labels dan mempertahankan source/record timestamps.

Backend feature-based, UUID/NUMERIC/TIMESTAMPTZ, CHECK/FK/index, transactional writes, optimistic conflict, create idempotency, ownership dan kedua consent untuk descriptive read. Tidak mengganti Better Auth, profil atau onboarding. Audit memuat metadata operasi, tanpa payload kesehatan. Tidak ada dependensi aplikasi baru.

## Artefak

- [Desain dan screen/API contract](../design/nutrition-figcraft-spec.md); editable source existing `design/beOkay-ui.figcraft` halaman 10 Nutrition, enam frame dan rendered previews.
- [Arsitektur](../architecture/nutrition.md), [schema/data dictionary](../database/nutrition-schema.md), [API](../api/nutrition.md).
- [Hasil tes/Appium dan screenshot](../testing/nutrition.md); Bruno folder 09 Nutrition memperluas satu collection existing.

MCP desktop attach belum stabil; desain native headless berhasil dibuat, dirender dan diperiksa. Tidak ada klaim halaman 09/11–19 lengkap, responsive design editable lengkap, user approval atau pixel-perfect parity. Palet/tema Inter existing dipakai tanpa foto tambahan.

## Database dan API

Migration `20261108070202_nutrition`: food_catalog, meal_logs, meal_items, record_revisions. Back-relations ke Users saja yang ditambahkan pada model auth. Migrasi tidak diterapkan ke dev/produksi. CHECK gram memeriksa null/provenance secara eksplisit. Drift check hanya menyisakan noise default UUID empat tabel auth.

Rute food search/create/update; meal create/list/detail/patch/revisions; derived meal-only timeline; daily Nutrition summary; Today enhanced. Semua private, verified-session/owner/health-consent scoped; descriptive summaries membutuhkan purpose terpisah. Tidak membuat tabel summary/outbox/sync sebelum slice yang membutuhkannya. Daily/list memakai source snapshot konsisten dalam RepeatableRead.

## Bukti verifikasi

Backend: **6 pass, 106 expect calls**; Flutter: **33 pass**; Bruno: **19/19 request dan test pass**; Appium: **12 skenario terverifikasi** terhadap API/PostgreSQL nyata. Typecheck backend, flutter analyze, build APK debug, dan pemeriksaan whitespace berhasil pada perubahan yang diverifikasi. Laporan pengujian mencatat perintah serta batas buktinya.

Kegagalan yang benar-benar ditemukan dan diperbaiki: navigasi root history/detail tanpa jalan kembali Today; filter arsip+tanggal tidak sinkron; koreksi tanpa foodId menghilangkan snapshot; nama item bebas tidak berubah; notes-only tidak memicu discard guard; validation error mengunci input. Red/green evidence ada pada tes dan keluaran sesi. Konflik versi menuntut reload untuk meninjau perubahan, tidak menimpa diam-diam.

## Acceptance dan batas yang tersisa

Selesai untuk slice ini: fitur Nutrition **online** beserta persistence/API/UI/history/correction/archive, integrasi Today, meal timeline/daily read, desain native, Bruno dan verifikasi di atas. Quick Record food aktif; pilihan domain lain adalah preview disabled. Full FEAT-01/02/08/09/10 bukan selesai hanya karena integrasi Nutrition ada.

Belum: offline local health persistence/sync/conflicts antarperangkat; tab Log/Insights penuh; multi-domain/persistent daily/weekly summaries; dataset nutrisi eksternal terverifikasi/portion conversions; foto/recipes; food-catalog editing UI; arbitrary-IANA input picker (form memakai zona perangkat berlabel, history memakai preferensi); iOS/perangkat fisik/audit aksesibilitas penuh. Data policy/legal consent existing masih draf. Tidak ada diagnosis, target medis otomatis, saran obat atau klaim kausal.

Next action: pengguna mereview kode dan artefak Nutrition. Setelah diminta lanjut ke fitur berikutnya, kerjakan Slice 3 Glucose dan berhenti lagi. Tidak melakukan git add/commit/push.
