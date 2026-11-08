# Activity — laporan implementasi Slice 4

Status: **VERIFIED untuk Activity online**, berhenti sebelum Medication agar pengguna dapat membaca kode. Seluruh P0/P1 belum selesai. Emulator GUI dan API uji sengaja tetap aktif atas permintaan pengguna.

## Audit dan implementasi

Working tree bersih saat mulai; Nutrisi/Glukosa sudah menjadi fondasi existing. Activity backend/schema/Flutter sebelumnya MISSING, Today/Quick Record masih preview. Better Auth, consent, onboarding, profil/preferensi, tema dan pola revision/account-scoped write dipakai kembali. Root README tidak tersedia; README server/app masih scaffold, sehingga sumber dan dokumen arsitektur menjadi bukti kondisi aktual.

Urutan yang dijalankan: audit → desain native FigCraft/data dictionary/UI–API contract → tes merah → migrasi → API/domain → Flutter → integrasi Today/timeline → verifikasi dan laporan. Tidak ada git add/commit/push, sub-agent atau migrasi dev/produksi. Checkpoint tersimpan di laporan ini karena memory/plan MCP bersama tidak tersedia.

Fitur tersambung: Today → shared Quick Record → form aktivitas manual → PostgreSQL → detail/histori → koreksi/revisi → archive/restore → total harian/mingguan dan event timeline tiga domain. Jenis awal jalan kaki, bersepeda, lari, latihan kekuatan dan lainnya. Durasi menentukan waktu selesai; jarak/langkah opsional tetap null bila tidak diketahui. Intensitas dilaporkan sendiri. Sumber hanya manual, tanpa kalori/GPS/heart-rate rekaan.

## Database dan kontrak

Migration `20261108130338_activity`: activity_sessions dan activity_id pada record_revisions, FK Users UUID, index owner/start-time/ID, unique revision/version, CHECK sumber/state/numerik/end=start+duration dan tepat satu sumber revisi. Existing auth hanya ditambah relasi balik; tidak ada duplicate user. [Data dictionary](../database/activity-schema.md), [arsitektur](../architecture/activity.md).

Create idempotent UUID/hash, koreksi transactionally owner/version-scoped dengan snapshot lama dan alasan. Sparse patches mempertahankan omitted fields. Semua endpoint health-consent/verified-session scoped; summary memakai consent tambahan. Metadata audit tidak menyimpan payload kesehatan. [API contract](../api/activity.md): create/list/detail/PATCH/revisions, daily/weekly Activity summary, Today/daily composite dan timeline extended.

Ringkasan mengambil source aktif pada rentang tanggal lokal, recompute on read. Minggu mengikuti Intl.Locale.getWeekInfo: id-ID mulai Minggu; timezone menentukan batas kalender PostgreSQL termasuk DST. Seluruh sesi masuk tanggal mulai, termasuk lintas tengah malam. Durasi adalah jumlah sesi yang dilaporkan, bukan unique active time. Review-flagged sessions tetap terlihat tetapi tidak masuk total; optional totals memiliki UNKNOWN/PARTIAL/COMPLETE coverage. Null durasi saat tidak ada eligible record tidak menyatakan pengguna tidak aktif.

## Desain dan Flutter

Native page4085 `12 — Activity` pada `design/beOkay-ui.figcraft`, lima frame editable dibuat/dirender sebelum UI. Overview dan PNG handoff diperiksa. [Desain/screen matrix](../design/activity-figcraft-spec.md). Palet/Inter existing, charcoal editorial card, pill controls dan layout scrollable dipakai. Tidak ada aset foto berlisensi terverifikasi sehingga tidak mengklaim fotografi baru. Tidak mengklaim desktop MCP attach, approval desain pengguna atau pixel-perfect parity.

Flutter feature data/application/presentation mencakup form, history/date/archive/pagination, detail/provenance/revisions dan weekly day selector yang membuka histori bertanggal. Shared EditorialFeatureCard mengikuti token existing. Provider mengikuti auth/consent/preferences dan menginvalidasi detail/list/daily/weekly/Today sesudah mutation. HTTP400 tetap editable,503 mempertahankan retry payload,409 meminta reload. Unsaved guard aktif. Form waktu memakai zona perangkat berlabel; histori mengikuti preferensi.

## Verifikasi aktual

- Backend: **15 tes lulus,264 expect calls**, termasuk regresi auth/Nutrisi/Glukosa.
- Flutter: **52 tes lulus**;9 tes Activity juga lulus di `TZ=America/New_York`.
- Bruno: **57/57 requests/tests lulus**,20 Activity cases.
- Appium: **10 pemeriksaan alur** pada emulator/API nyata, termasuk simpan30→koreksi25 menit, partial weekly total70, archive45→restore70 dan versi4.
- Typecheck, Flutter analyzer, APK debug dan whitespace check lulus. Drift hanya noise UUID-default empat tabel auth.

[Perintah, red/green, cakupan dan screenshot](../testing/activity.md). Defect yang diperbaiki dengan bukti: label Activity pada preview sempat memakai fallback Glucose; week navigation memakai elapsed days sehingga tanggal salah saat DST fallback; filter tanggal gagal untuk selected week mendatang. Tidak menghapus/skip tes gagal atau mengklaim widget fake backend sebagai E2E.

## Acceptance dan batas

Activity manual **online** siap review beserta API/persistence/UI/history/correction/summary/integrasi/desain/Bruno/tes. Ini bukan full P0: Medication, Goals, full Log/Insights, global/persistent weekly summaries, offline durable drafts/queue/sync/conflict review dan privacy offline belum selesai. Goal-progress integration menunggu FEAT-07. Semua P1 tetap belum diimplementasikan.

Tidak ada diagnosis, target latihan medis, saran dosis, klaim kausal, calorie estimate atau data wearable. Composite Today bukan satu atomic cross-domain snapshot. iOS/perangkat fisik, semua screen-reader flows, audit aksesibilitas penuh, production benchmarks serta tinjauan kebijakan consent/retensi belum dinyatakan selesai.

Emulator `Android Emulator — Pixel_4:5554` benar-benar IsViewable di desktop host. APK terbaru dan API uji localhost3300 tetap berjalan agar pengguna dapat melihat/mencoba aplikasi. Data sintetis berada di database uji, bukan dev/produksi; menghentikan stack tmpfs akan menghapus fixture tersebut.

Next action: pengguna meninjau kode Activity; setelah diminta lanjut ke fitur berikutnya, implementasikan Medication dan berhenti kembali. Jangan commit/push atau otomatis mematikan emulator yang diminta pengguna tetap terlihat.
