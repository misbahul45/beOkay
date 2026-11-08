# Activity — hasil pengujian Slice 4

8 November 2026. Backend execution seluruhnya di Docker, PostgreSQL/Mailpit terisolasi. Flutter/Dart di host sesuai aturan proyek. Database dev/produksi tidak dimigrasi.

| Pemeriksaan yang dijalankan | Hasil |
|---|---|
| Docker tester, seluruh Bun tests | **15 pass, 0 fail; 264 expect calls**, 8 berkas |
| Typecheck API di api-test | Lulus |
| Prisma migrate diff di container | Hanya noise UUID-default empat tabel auth |
| `flutter test` dari app/ | **52 pass** |
| `TZ=America/New_York flutter test test/flows/activity_test.dart` | **9 pass**, termasuk DST fallback |
| `flutter analyze` | No issues found |
| `flutter build apk --debug --no-pub` | Lulus |
| Bruno collection dalam Node22 container | **57/57 requests/tests pass**, 20 Activity |
| Appium MCP, API nyata | **10 pemeriksaan alur** di bawah |
| FigCraft CLI | Native page 4085/lima frame, render dan handoff diperiksa |
| Whitespace dan file ownership | Bersih pada perubahan diperiksa; berkas milik user, bukan root |

Bruno assertions counter 0/0 karena assertions berada dalam tests blocks; 57 tests tetap dijalankan. Angka tersebut tidak berarti seluruh master P0 journey selesai.

## Bukti perilaku dan red/green

Red unit gagal karena module Activity belum ada, integration route 404 vs expected 401, Flutter import belum tersedia. Model tests lalu lulus untuk bounds/duration/end, optional null/explicit 0/partial totals, review exclusion, locale first-day dan kalender year/DST boundary. Integration lifecycle memverifikasi authenticated consent/owner, create retries concurrent, mismatched payload 409, concurrent corrections 200/409, revisions/sparse notes, archive/restore/date filter, database CHECK, daily/weekly source totals, Today/daily composite, timeline filtering/tie pagination, expired session dan withdrawal kedua consent.

Cross-midnight DST example: start 2026-03-09T03:30Z di New York masuk 8 Maret 23:30; seluruh 60 menit masuk tanggal mulai, bukan tanggal 9 Maret. Pengujian weekly menggunakan calendar bounds, bukan 168 jam. Correction start-now dengan durasi 45 ditolak 422 karena sesi belum selesai.

Flutter tests: validasi duration dan optional metric, narrow 320px/text scale 2 form/week, selected day→date-filtered history, account-changed write rejection, HTTP 400 editable/409 reload/503 same-payload retry, source navigation Activity di Today, serta regresi identity/Nutrisi/Glukosa. Red Today membuktikan label type Activity sempat jatuh ke Glucose. Red DST di environment New York: next week Nov 1→Nov 7 padahal expected Nov 8; perbaikan memakai kalender UTC date-only. Red future history date memicu DatePicker initialDate>lastDate; input awal kini di-clamp dengan aman. Semua tes terkait dijalankan ulang tanpa skip.

## Appium dan host emulator

Pixel_4 emulator-5554, Android 17/API37, UiAutomator2, 1080×2280. Fixture memakai password random runtime, verified email di DB uji dan onboarding lewat API. Login dan interaksi fitur melalui UI. Token/password hanya temporary storage, tidak di repo/laporan. API hanya 127.0.0.1:3300; ADB reverse tcp3000→3300.

1. Login akun sintetis→Today dengan data akun yang benar.
2. Quick Record→Activity, walking 30 menit/moderate/note, unknown km/steps.
3. Detail/API: end-start 1800000ms, source manual, null metrics, versi 1.
4. Koreksi UI 25 menit/alasan→versi 2, end bergeser 5 menit, original 30 menit tetap di revision.
5. History/weekly:2 sesi total 70 menit, km 2.5 dan langkah 0 diberi partial coverage 1/2.
6. Weekly selected day→histori bertanggal, membuka source detail yang sesuai.
7. Archive/alasan→total mingguan 45 menit dan 1 sesi aktif.
8. Filter Arsip→restore/alasan→versi 4, total 70 menit/2 sesi; revision 3/2/1 tersimpan.
9. APK terbaru dipasang ulang/diaktifkan; sesi dan data persisted tetap tersedia.
10. Preview Today Activity membuka original session versi 4.

Interaksi MCP terotomasi, belum standalone CI Appium runner. Locator memakai accessibility/native descriptions; field hint/W3C keys; offscreen melalui scroll_to_element. Persisted values diperiksa lewat API yang benar-benar membaca PostgreSQL. Tidak menganggap tap atau fake backend sebagai bukti save.

Atas permintaan pengguna, headless emulator diganti jendela GUI host. `xwininfo` memverifikasi `Android Emulator - Pixel_4:5554`, 407×864, MapState IsViewable. Emulator dan API uji **tetap aktif** untuk review; jangan otomatis down-v/kill setelah membaca laporan ini. Tidak ada perubahan stack dev.

Screenshot sintetis: [form](artifacts/activity-appium/form.png), [detail](artifacts/activity-appium/detail.png), [weekly](artifacts/activity-appium/weekly.png), [restored](artifacts/activity-appium/restored.png), [Today](artifacts/activity-appium/today.png). Screenshot final benar-benar dibuka untuk inspeksi; tidak tampak overflow di viewport yang diperiksa, konten bawah dapat di-scroll. Bukan sertifikasi semua layar/ukuran, iOS, perangkat fisik atau aksesibilitas menyeluruh.

[Hasil terstruktur](artifacts/activity-appium/results.json) mencatat observasi dan status jendela host tanpa kredensial.

## Replay

```bash
docker compose -f compose.test.yaml up -d --wait api-test
docker compose -f compose.test.yaml run --rm tester bun test
docker compose -f compose.test.yaml exec -T api-test bun run typecheck
docker compose -f compose.test.yaml exec -T api-test bun run db:migrate:diff -- --from-config-datasource --to-schema prisma/schema.prisma --script
```

Selama host app memakai API test, gunakan override yang sama pada compose up/run agar port localhost3300 tidak hilang karena recreate container. Dari app/: `flutter analyze`, `flutter test`, DST command di atas dan `flutter build apk --debug --no-pub`.

Bruno: `bru run --env test` dari docs/api/bruno dalam container pada network beokay-test_default. Inject runtime sessionToken,otherSessionToken,restrictedSessionToken,newMealId,newGlucoseId,newActivityId,eventTime. Fresh akun/ID untuk correction 1→4; actor berbeda full consent, restricted health-only; eventTime sesi sudah selesai. CLI tidak menambah dependensi aplikasi. Script bootstrap/credentials sementara hanya di /tmp.

Jika pengguna sudah selesai dengan emulator, cleanup yang sesuai adalah delete sesi Appium milik pengujian, remove reverse, stop emulator dan `docker compose -f compose.test.yaml down -v`. Jangan menjalankan cleanup sekarang karena pengguna meminta aplikasi terlihat. Offline/sync, goal progress, global weekly Insights, P1 dan CI mobile runner belum termasuk slice ini.
