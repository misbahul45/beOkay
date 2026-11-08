# Glucose — pengujian Slice 3

8 November 2026. Backend di Docker dengan PostgreSQL/Mailpit uji terisolasi; Flutter/Dart di host. Tidak menguji atau menerapkan migrasi pada database dev/produksi.

| Pemeriksaan dijalankan | Hasil aktual |
|---|---|
| `docker compose -f compose.test.yaml -f /tmp/glucose-appium.yaml run --rm tester bun test` | **11 pass, 0 fail; 188 expect calls**, enam berkas |
| Typecheck API di api-test | Lulus |
| Prisma migrate diff di container | Hanya noise default UUID empat tabel auth; tidak ada drift Glucose/Nutrition |
| `flutter test` dari app/ | **42 pass** |
| `flutter analyze` | No issues found |
| `flutter build apk --debug --no-pub` | Lulus; APK diuji di emulator |
| Bruno seluruh collection | **37/37 requests/tests pass**: 18 Glucose + 19 existing |
| Appium MCP, API nyata | **10 pemeriksaan alur** di bawah |
| Native FigCraft | Lima frame editable diverifikasi, dirender dan ekspor individual diperiksa |
| `git diff --check` | Lulus pada perubahan yang diperiksa |

Angka tersebut bukan seluruh master journey P0. Bruno memakai tests blocks: counter assertions CLI 0/0 sementara 37 tests benar-benar dijalankan.

## Red/green dan cakupan

Red unit Glucose gagal karena modul belum ada. Tes konversi mencakup faktor existing 18.016, source hingga 4 desimal, canonical Decimal dan rounding display; 5.1234 mmol/L → 92.3031744 mg/dL. Tes menemukan default Zod pada partial patch yang mereset field. Notes-only kini tidak menyisipkan default source/context/unit/quality. Red regresi Nutrition membuktikan archive-only mengosongkan notes, lalu diperbaiki.

Integrasi API→PostgreSQL: session/consent, create/retry identik, conflicting payload, source/canonical persistence, display preference tanpa perubahan versi, concurrent correction 200/409, snapshots, quality/eligibility, daily/Today, same-timestamp meal+glucose timeline, pagination/filter, archive+date, CHECK, expired session, consent withdrawal dan cross-user read/write/revisions. DST New York: 2026-03-09T03:30Z masuk 8 Maret 23:30 pada hari 23 jam; concurrent create retry tetap satu record.

Red Flutter gagal saat fitur belum ada. Widget menemukan background kartu menutupi Material ancestor ExpansionTile/ListTile; HealthCard diperbaiki. Red Today preview tidak menemukan event sebelum feed source-linked diterapkan. Flutter mencakup unit asli ketika display berbeda, invalid numeric domain, captured-session writes/rejection, empty history/root back, graph 320px/text scale 2, Today→original record, HTTP 400 tetap editable, 409 reload, 503 same-payload retry dan regresi auth/onboarding/Nutrition. Fake backend bukan bukti E2E.

Percobaan integration awal memakai service tanpa API_BASE_URL dan API proses lama memberi 404. Diperbaiki dengan tester/restart. Hasil tabel berasal dari run final dengan environment benar; tidak menghapus/skip tes gagal.

## Appium nyata

Pixel_4 emulator-5554, Android 17/API37, UiAutomator2, 1080×2280. Fixture password random runtime; email verified di DB uji dan onboarding melalui API. Login/interaksi fitur melalui UI. Fixture/helper hanya di /tmp; token/password tidak di repository/laporan. API sementara 127.0.0.1:3300; ADB reverse tcp3000→3300.

1. Login sintetis→Today data akun persisted.
2. Quick Record→Glucose 5.5 mmol/L, setelah makan/note; API satu record canonical 99.088, versi 1.
3. Detail 99 mg/dL, original 5.5 mmol/L, sumber glukometer/jenis kapiler.
4. Koreksi UI 6.1 mmol/L → canonical 109.8976, versi 2; note/context tetap dan revisi 1 terlihat.
5. History menampilkan dua pengamatan dan summary dengan source/coverage/grafik titik.
6. Setting display→mmol/L; API display 6.1, canonical 109.8976 dan versi 2 tetap.
7. Archive/alasan → versi 3; summary count 2→1, mean null; notes/nilai tetap.
8. Filter Arsip→detail→restore/alasan → versi 4, archivedAt null; summary count 2/READY.
9. Restart emulator/app dan install APK terbaru mempertahankan sesi/data; Today benar setelah ADB/retry.
10. Today preview urut Glucose 18:38, Meal 18:30, Glucose 18:30; tap pertama menuju record asli versi 4.

MCP interaktif terotomasi, belum runner Appium mandiri siap CI. Interupsi menghentikan emulator; emulator/reverse dipulihkan dan API diverifikasi sebelum lanjut. ListTile memakai merged accessibility descriptions, offscreen via scroll_to_element, field hint/W3C keyboard. Nilai 6.1 diperiksa pada screenshot/API, bukan diasumsikan dari tap.

Screenshot sintetis yang benar-benar dibuka untuk inspeksi:

- [Detail source/display](artifacts/glucose-appium/detail.png)
- [Form koreksi/keyboard](artifacts/glucose-appium/correction-form.png)
- [Perubahan display](artifacts/glucose-appium/converted-preference.png)
- [Pemulihan versi 4](artifacts/glucose-appium/restored.png)
- [Today timeline](artifacts/glucose-appium/today-timeline.png)

[Catatan hasil terstruktur](artifacts/glucose-appium/results.json) menyimpan cakupan observasi tanpa kredensial. Cleanup sesi Appium, ADB reverse, emulator dan stack uji selesai; berkas kredensial sementara dihapus. Kode fitur tidak di-commit.

Tidak tampak overflow pada screenshot final yang diperiksa. FigCraft sempat memiliki overflow nested text dan diperbaiki sebelum ekspor. Bukti tidak mencakup iOS/perangkat fisik, audit screen-reader lengkap, semua ukuran, durable offline atau semua journey P0.

## Replay

```bash
docker compose -f compose.test.yaml up -d --wait api-test
docker compose -f compose.test.yaml run --rm tester bun test
docker compose -f compose.test.yaml exec -T api-test bun run typecheck
docker compose -f compose.test.yaml exec -T api-test bun run db:migrate:diff -- --from-config-datasource --to-schema prisma/schema.prisma --script
```

Dari app/: `flutter test`, `flutter analyze`, `flutter build apk --debug --no-pub`.

Bruno: `bru run --env test` dari docs/api/bruno dalam container Node pada network beokay-test_default. Inject sessionToken,otherSessionToken,restrictedSessionToken,newMealId,newGlucoseId,eventTime via runtime --env-var. Dua pemilik berbeda mempunyai health+summary consent; restricted hanya health. Gunakan akun/UUID baru tiap run karena corrections berurutan versi 1→4. CLI sementara npx @usebruno/cli dalam node22 tidak menambah dependensi aplikasi. Ikuti bootstrap auth/onboarding pada integration identity, tanpa literal credentials.

Appium: emulator, API override localhost, ADB reverse, APK, select_device/create UiAutomator2; ulangi daftar dan verifikasi persisted API/DB. Setelah selesai, bersihkan sesi/reverse/emulator yang dibuat sendiri serta `docker compose -f compose.test.yaml down -v`. Jangan membersihkan stack dev. Offline/sync, weekly summaries, full Log/Insights tabs, CGM/P1 dan CI Appium runner belum termasuk.
