# Nutrition — pengujian Slice 2

Tanggal 8 November 2026. Semua backend execution di Docker, PostgreSQL/Mailpit uji terisolasi. Flutter/Dart di host sesuai aturan proyek. Tidak menguji terhadap DB dev/produksi.

## Hasil aktual

| Pemeriksaan | Hasil |
|---|---|
| `docker compose -f compose.test.yaml run --rm tester bun test` (dengan override port sementara selama Appium) | 6 pass, 0 fail, **106 expect calls** di 4 berkas |
| Typecheck API di api-test | Lulus |
| `bun run db:migrate:diff -- --from-config-datasource --to-schema prisma/schema.prisma --script` di container | Hanya default gen_random_uuid pada 4 tabel auth; tidak ada drift tabel Nutrition |
| `flutter test` | **33 pass** |
| `flutter analyze` | No issues found |
| `flutter build apk --debug --no-pub` | Lulus |
| Bruno | **19 request / 19 tests pass**: 16 Nutrition + 3 Today/security; assertions counter 0/0 karena assertion berada dalam tests blocks |
| Appium MCP | **12 skenario terverifikasi**, API dan DB nyata |

Red tests merekam modul Nutrition belum ada, root history tanpa jalan kembali Today, filter arsip+tanggal kosong, snapshot referensi hilang saat foodId tidak dikirim ulang, notes-only tidak dilindungi discard guard, dan input terkunci setelah 400. Semua regresi terkait diperbaiki. Fixture test awal perlu inisialisasi locale dan GoRouter; ini diperbaiki pada tes, bukan disamarkan sebagai error produk. Assertion PrismaPromise dibungkus Promise agar kompatibel dengan Bun expect.

Backend mencakup multiple items, null/partial nutrients, snapshot tetap setelah katalog diubah, quantity correction, concurrent expectedVersion 200/409, revisions, archive, date-filter arsip, source ownership, session/consent, duplicate create, pagination, source-to-Today/daily/timeline lifecycle, PostgreSQL CHECK, dan hari DST 23 jam. Nilai energi test adalah fixture sintetis, bukan klaim nutrisi makanan nyata.

Flutter menguji label unknown/partial, required items, capture acting session dan penolakan account change sebelum HTTP, jalur history-root ke Today, discard notes-only, validation error tetap editable, serta regresi identity/Today existing. Tes fake backend bukan bukti E2E. Tidak ada klaim semua form/state telah memiliki widget test tersendiri atau semua ukuran terverifikasi.

## Appium nyata

AVD Pixel_4 (`emulator-5554`), Android 17/API37, 1080×2280, UiAutomator2. APK debug dipasang tanpa menghapus data. API uji dipublikasikan sementara hanya ke 127.0.0.1:3300, ADB reverse tcp3000→3300. Akun sintetis verified + onboarding lengkap dibuat di DB uji; login dan seluruh interaksi berikut melalui UI. Skrip fixture/kredensial hanya di `/tmp` dan dibangkitkan saat runtime.

[Hasil terstruktur](artifacts/nutrition-appium/results.json) mencatat 12 observasi: login/Today; Quick Record→form/item; persistensi/detail unknown; koreksi versi2; histori; restart/Today; arsip versi3; kembali Today/jumlah turun; pemulihan versi4; makanan pribadi dengan source/null nutrients; cari katalog/150g→300kkal; discard catatan belum disimpan.

Interaksi MCP bersifat terotomasi tetapi bukan suite Appium runner mandiri yang siap CI. Locator awal disesuaikan untuk semantics ListTile yang menggabungkan judul/subtitle. Pengisian nilai default melalui setValue dapat menambah teks; quantity final diverifikasi, dan koreksi numeric memakai key events ketika diperlukan. Salah satu dropdown membuat native source/bounds terlambat diperbarui; foreground/resume dan fokus input ulang dipakai, lalu nilai **yang tersimpan** 150g dan 300kkal diperiksa. Tidak mengklaim tap yang tidak menghasilkan perubahan sebagai sukses.

Bug produk yang ditemukan Appium: detail/history setelah context.go bisa tidak mempunyai jalan kembali Today. Ditambah tes regresi yang gagal, lalu back/home actions diperbaiki dan diuji ulang pada APK. Pemeriksaan lanjutan memperbaiki perlindungan notes-only dan handling validation/conflict; discard juga diverifikasi lagi lewat Appium.

Screenshot benar-benar dibuka untuk inspeksi. Bukti mencakup beberapa waktu selama pengujian; count Today bergantung fixture yang ada saat capture. Semua data pada gambar sintetis. Tidak tampak overflow pada viewport yang diperiksa; belum ada audit penuh iOS, screen reader, perangkat fisik atau semua ukuran.

- [Quick Record](artifacts/nutrition-appium/quickRecord.png)
- [Form makanan](artifacts/nutrition-appium/mealForm.png)
- [Histori](artifacts/nutrition-appium/mealHistory.png)
- [Today dengan catatan nyata](artifacts/nutrition-appium/todayNutrition.png)
- [Detail katalog dan 300 kkal](artifacts/nutrition-appium/catalogMeal.png)
- [Konfirmasi perubahan belum disimpan](artifacts/nutrition-appium/unsavedGuard.png)

## Replay dan cleanup

```bash
docker compose -f compose.test.yaml up -d --wait api-test
docker compose -f compose.test.yaml run --rm tester bun test
docker compose -f compose.test.yaml exec -T api-test bun run typecheck
docker compose -f compose.test.yaml exec -T api-test bun run db:migrate:diff -- --from-config-datasource --to-schema prisma/schema.prisma --script
```

Flutter: `flutter test`, `flutter analyze`, `flutter build apk --debug --no-pub` dari app/. Bruno: dari root collection, `bru run --env test` dengan sessionToken, restrictedSessionToken, newMealId dan eventTime diinjeksi saat runtime, pada network Docker beokay-test_default. Restricted fixture punya health consent tetapi tidak summary consent.

Untuk Appium, nyalakan emulator dan API dengan override port localhost, pasang APK, ADB reverse, pilih device lalu buat session UiAutomator2; ulangi daftar skenario. Sesi Appium, emulator headless, reverse dan stack uji yang dibuat sendiri dibersihkan setelah verifikasi. Jangan menjalankan cleanup pada compose dev. Setelah perubahan dependensi, rebuild image dan down -v volume node_modules sesuai AGENTS.md.

P1 foto/recipes, offline durable queue, sync/restart replay, full cross-domain timeline, persistent daily/weekly summary dan clinical metrics belum termasuk slice ini.
