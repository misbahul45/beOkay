# beOkay 3.0 — Fase 7: Pengerasan dan kesiapan pilot

> Tanggal: 11–12 November 2026. Cakupan dari rencana di [phase-0-2 §7](beokay-3.0-phase-0-2.md): F-01, F-02, F-03, CI (F-06), registri model (F-16), tinjauan klinisi (F-11), ditambah temuan audit kecil yang bisa ditutup tanpa keputusan pemilik. Fase ini tidak menambah layar baru, jadi tidak ada desain FigCraft baru.

## 1. Ringkasan

| Butir | Hasil | Status |
|---|---|---|
| Bug dari pengecekan Fase 6 (push pengingat, teks 2×, ringkasan gizi) | perbaikannya sudah ada di pohon kerja; kini dijaga tes regresi | **terverifikasi** |
| F-11 keselamatan Asisten | `safety-policy-v2` + korpus adversarial 99 kalimat + paket tinjauan klinisi | **sebagian**: tinjauan klinisi belum dilakukan |
| F-16 registri model | `scripts/ml/register-model.ts` + kartu model + validasi | **ditutup** |
| F-06 CI | `.github/workflows/ci.yml` (gitleaks, backend, Flutter) | **ditutup**, belum pernah berjalan di GitHub |
| F-03 rilis Android | build rilis diverifikasi ulang setelah Fase 6 | **sebagian**: kunci rilis dan Firebase milik pemilik |
| F-01, F-02 | tetap tertutup; ekspor memuat tabel Fase 6 (`recognitions`, `notifications`, `notification_preferences`) | **ditutup** |
| Cadangan basis data | `scripts/ops/db-backup.sh` dan `db-restore.sh`, diuji pulang-pergi | **siap**, penjadwalan belum dipasang |
| F-05, F-07, F-08, F-09, F-14, F-17 | lihat §6 | ditutup atau sebagian |
| Pilot (P3-13) | [rancangan protokol](../research/pilot-protocol.md) dan daftar gerbang | **draf**, menunggu etik |

Kriteria terima fase ("semua pemblokir rilis tertutup") **belum terpenuhi**: yang tersisa hanya bisa dilakukan pemilik (kunci rilis, pendaftaran Firebase, tinjauan klinisi, persetujuan etik, tinjauan hukum teks consent). Semua pekerjaan kode yang tidak bergantung pada pemilik sudah dikerjakan.

## 2. Bug dari pengecekan Fase 6

Ketiga perbaikan yang dilaporkan di akhir Fase 6 ada di kode:

| Bug | Perbaikan di kode | Penjaga regresi |
|---|---|---|
| Sakelar "Notifikasi push" dan "Pengingat" tidak berpengaruh pada push pengingat; ketukan push selalu ke kotak masuk | `push-dispatcher.ts` memanggil `pushAllowed(prefs, "REMINDER")` (dihitung `skippedByPreference`) dan mengirim `{action, refId}` dari `reminderTarget`; `push_client.dart` membuka tujuan itu | `server/tests/integration/push.test.ts` (sudah ada sejak Fase 6) |
| Baris status sambungan di kotak masuk keluar layar pada teks 2× | teks status di dalam `Expanded` | **baru** `app/test/flows/large_text_regressions_test.dart`: kotak masuk pada 360 dp dan teks 2× tanpa overflow. Uji mutasi: tanpa `Expanded` tes gagal ("RenderFlex overflowed by 486 pixels"), dipulihkan lulus |
| Nama pencapaian terpotong di tengah kata pada teks 2× | `RecognitionBadge` menjadi baris selebar layar saat teks besar | tes baru: lebar 120 pada 1×, > 300 dan berupa `Row` pada 2× |
| Ringkasan gizi berupa kartu di dalam kartu | `NutritionTotals` berisi `DetailRow` langsung di `DetailSection` | tes baru: satu judul, tidak ada `Card` di dalam ringkasan, satu baris per zat gizi |

## 3. Keselamatan Asisten (`safety-policy-v2`, F-11)

### 3.1 Yang berubah

- **Satu sumber aturan.** Pola menyakiti diri dipindah dari `conversation.router.ts` ke `agent.safety.ts`. Sebelumnya hanya router percakapan yang memeriksanya; `createRun` di agen tidak. Kedua jalur kini memanggil `screenRequest` yang sama, dan `screenRequest` mengembalikan `urgent`.
- **Normalisasi**: singkatan dan ejaan chat (gak, bgt, nafas, sesek, pinsan, lemes, gemeteran, keringet, nurunin), huruf berulang ("sesaaak"), reduplikasi angka ("kejang2"), "deg-degan" → berdebar, beberapa kata Jawa/Sunda (semaput, klenger, kapiuhan, mumet, ngelu, lieur, kliyengan), akhiran -ku/-mu/-nya pada kata tubuh ("dadaku", "gulaku").
- **Aturan baru**: `GLUCOSE_EXTREME` (angka < 70 atau ≥ 300 mg/dL, < 3,9 atau ≥ 16,7 mmol/L, atau "gula drop/anjlok/tinggi banget"), `SYMPTOM_REVIEW` (luka kaki tidak sembuh/menghitam, kesemutan, haus terus dan sering kencing, pandangan kabur, demam tinggi), gugus tanda hipoglikemia (≥ 2 tanda), tanda stroke, ketoasidosis, overdosis/kelebihan insulin.
- **Urutan diperbaiki**: keadaan darurat diperiksa sebelum larangan saran obat. Pada v1, "aku kelebihan suntik insulin, sekarang gemetar" mendapat penolakan saran obat; di v2 mendapat pesan darurat.
- **Positif palsu v1 yang ditutup**: "olahraga maksimal 20 menit" (dulu diblokir sebagai eskalasi intensitas), "lagi patah hati" (dulu cedera), "aku tidak sadar sudah makan 3 piring" (dulu darurat), kata "spain"/"painting" (dulu cocok dengan "pain").
- Kartu keselamatan di percakapan memakai `isUrgentSafetyCode`; `SYMPTOM_REVIEW` berjudul "Perlu tenaga kesehatan". Versi kebijakan tersimpan di rekomendasi dan peristiwa `SAFETY_SCREEN` (`safety-policy-v2`).

### 3.2 Bukti

- `tests/fixtures/safety-corpus.ts`: 99 kalimat (71 harus terdeteksi dengan kode tertentu, 28 harus lolos), diberi tag parafrase/typo/slang/Jawa/Sunda/Inggris/idiom/angka. `tests/unit/agent-safety.test.ts` gagal bila satu kalimat pun salah kode, dan memeriksa setiap aturan punya contoh positif.
- Pembaca angka glukosa diuji pada batas (69/70, 299/300 mg/dL; 3,8/3,9 mmol/L), jam, sendok gula, dan selisih ("turun 30").
- `tests/integration/conversation.test.ts`: lewat API, "gulaku tadi 52" → `GLUCOSE_EXTREME` mendesak, "luka di kaki gak sembuh2" → `SYMPTOM_REVIEW`, "aku capek hidup" → `SELF_HARM` mendesak; tidak ada run atau saran yang dibuat.

### 3.3 Yang belum

Tidak ada tenaga kesehatan yang meninjau ambang, aturan, atau pesan. Ambang tinggi 300 mg/dL adalah usulan produk. [Paket tinjauan klinisi](../research/safety-clinical-review-packet.md) berisi tabel aturan dan pesan lengkap, cara normalisasi, kelemahan yang terverifikasi (mis. "apa itu hipoglikemia?" dan "saya tidak pingsan kok" memicu kartu darurat; "rasanya mau ambruk" dan "lemas banget" lolos; "gula 18" dibaca 18 mmol/L), delapan pertanyaan untuk klinisi, dan lembar persetujuan kosong.

## 4. Registri model (F-16)

`docker compose run --rm -v <folder-kaggle>:/data:ro api bun run scripts/ml/register-model.ts dish-classifier <versi> /data [--expect-sha <sha>] [--dry-run]`

- SHA-256 dihitung dari `model.pt`; `--expect-sha` membandingkannya dengan `current.json` di Modal.
- `intended_use`, `training_data_provenance`, `feature_schema_version`, `endpoint_ref` dari kartu model `server/scripts/ml/model-cards/dish-classifier.json` (nilai sama dengan baris DB dev).
- `evaluation` diringkas dari `metrics.json`: uji penuh, uji tanpa duplikat, audit kebocoran, kelas, suhu, batasan; matriks per kelas tidak disimpan.
- Ditolak bila tidak ada uji tanpa duplikat, audit kebocoran, atau batasan; `classes.json` berbeda dari `metrics.json`; SHA tidak cocok; atau versi yang sama sudah terdaftar dengan artefak lain (`MODEL_VERSION_SHA_CONFLICT`). Artefak yang sama → `UNCHANGED`.
- Status selalu `RESEARCH_ONLY`; menaikkan status tetap lewat `set-model-status.ts`.
- Tes: `tests/unit/model-registry.test.ts` (3) dan `tests/integration/model-registry.test.ts` (3, menjalankan skrip sungguhan terhadap DB uji).

DB produksi masih belum punya baris model sampai pemilik menjalankan skrip ini dengan artefak Kaggle yang asli.

## 5. CI, cadangan, dan rilis Android

### 5.1 CI (F-06)

`.github/workflows/ci.yml`, pada push ke `main`, pull request, dan manual:

1. **Pemindaian rahasia**: gitleaks v8.30.1 pada pohon kerja dengan `.gitleaks.toml`. Satu positif palsu (`key: "PLANS_DONE_5"` di aturan pengakuan) dikecualikan lewat pola baris, bukan lewat path, sehingga token palsu yang disisipkan ke berkas yang sama tetap tertangkap (diuji dengan token GitHub dan AWS buatan).
2. **Backend**: build image uji, `compose.test.yaml`, `bun run typecheck`, `bun test`, log API bila gagal, `down -v`.
3. **Flutter** 3.44.4: `pub get`, `analyze`, `test`.

Workflow lolos `actionlint` 1.7.7 secara lokal. Workflow **belum pernah berjalan di GitHub**: perlu di-push oleh pemilik. Riwayat git lama tidak dipindai (pohon kerja saja), karena insiden sintetis 8 Nov (`d9a8749`) akan membuat pemindaian riwayat selalu gagal.

### 5.2 Cadangan basis data

`scripts/ops/db-backup.sh` (pg_dump format custom di dalam container, divalidasi dengan `pg_restore --list`, `.sha256`, izin 600, rotasi 14) dan `scripts/ops/db-restore.sh <berkas> --yes` (cek checksum, `pg_restore --clean --if-exists`). Diuji pada stack uji: baris sintetis `model_versions` dan ekstensi `vector`/`pg_trgm` pulih ke database baru; pemulihan dua kali berturut-turut aman; checksum rusak ditolak; tanpa `--yes` ditolak; rotasi menyisakan jumlah yang diminta. Penjadwalan (cron) dan salinan di luar mesin belum dipasang. Detail di [runbook §5](../operations/runbook.md).

### 5.3 Rilis Android (F-03)

`flutter build apk --release --dart-define=API_BASE_URL=https://api.beokay.invalid` dengan kunci sekali pakai di scratchpad: berhasil (83,9 MB). `aapt`: paket `id.beokay.app`, `INTERNET`, `POST_NOTIFICATIONS`, `CAMERA`, izin Health Connect baca (exercise, distance, steps), `c2dm.RECEIVE`. `apksigner`: ditandatangani kunci sekali pakai. APK, `key.properties`, dan kuncinya dihapus setelah pemeriksaan agar tidak tertukar dengan rilis asli.

## 6. Temuan audit lain

| Temuan | Perubahan |
|---|---|
| F-05 | `src/shared/http/rate-window.ts`: tujuh pembatas laju (agen, percakapan, ekspor, hapus akun, pemindaian foto, pencarian luar, pencarian web draf) memakai satu jendela geser yang membersihkan entri kedaluwarsa, jadi peta tidak tumbuh per pengguna yang sudah tidak aktif. Masih per proses; batas login Better Auth tetap `memory`. |
| F-07 | lima berkas kosong milik root (`server/crash-a.ts`, `crash-b.ts`, `live.ts`, `live2.ts`, `dish.jpg`) dihapus dari pohon kerja. |
| F-08 | `README.md` root; skrip `auth:generate` menunjuk `src/features/auth/auth.ts`; blok `LLM_*` yang tidak dibaca kode dibuang dari `.env.example`. |
| F-09 | linimasa meneruskan `activity_sessions.source` (sebelumnya semua aktivitas "manual"). |
| F-14 | `CONSENT_REQUIRED` di intervensi dan coaching menjadi `403`, sama dengan modul lain. Klien Flutter membaca `code`, jadi tidak ada perubahan di aplikasi. |
| F-17 | `emit()` agen mengambil `seq` dari nilai terbesar dan mengulang hingga 5 kali bila `UNIQUE(run_id, seq)` bentrok; Mailpit dipin `v1.33.0` di compose dev dan uji. |

Tidak diubah: F-10, F-12, F-13 (butuh keputusan pemilik: tujuan consent `product_analytics` yang tidak dipakai, locale `en-US` di CHECK, katalog makanan bersama, populasi sasaran dan `eligibility_status`), F-15 (stabilitas tes ulang cepat), polling SSE, cakupan Bruno, dan isi `AGENTS.md` yang usang ("Cakupan saat ini", "`app/` scaffold") karena itu instruksi agen milik pemilik.

## 7. Pengujian

| Lapisan | Hasil |
|---|---|
| Backend `bun test` (stack uji Docker dibuat ulang bersih) | **330/330**, 63 berkas; baru: `rate-window` (2), `model-registry` unit (3) dan integrasi (3), korpus keselamatan dan pembaca glukosa (4), sumber `health_connect` di linimasa, kartu keselamatan lewat API |
| `tsc --noEmit` | bersih |
| Flutter | **210/210**, `flutter analyze` bersih; baru `large_text_regressions_test.dart` (3) |
| gitleaks v8.30.1 | bersih pada salinan berkas yang akan di-commit (tracked + untracked non-ignored) |
| actionlint 1.7.7 | bersih |
| Build rilis Android | berhasil dengan kunci sekali pakai (§5.3) |
| Cadangan/pemulihan | pulang-pergi pada stack uji (§5.2) |

Tidak diverifikasi: CI di GitHub, push FCM di perangkat, emulator/ponsel (tidak ada perubahan UI selain tes), perilaku pesan keselamatan di depan pengguna nyata.

## 8. Yang harus dilakukan pemilik

1. Commit Fase 6 dan Fase 7 (termasuk penghapusan lima berkas kosong: `git add -A server/`), lalu push agar CI berjalan pertama kali.
2. Buat kunci rilis dan `key.properties` (runbook §6 butir 4); daftarkan `id.beokay.app` di Firebase dan taruh `google-services.json`.
3. Minta tenaga kesehatan meninjau [paket keselamatan](../research/safety-clinical-review-packet.md) dan mengisi lembar persetujuan.
4. Daftarkan model produksi dengan `register-model.ts` memakai artefak Kaggle asli.
5. Jadwalkan `db-backup.sh` di server produksi dan simpan salinan di luar mesin.
6. Ajukan [protokol pilot](../research/pilot-protocol.md) ke komite etik; tinjauan hukum teks consent.
7. Putuskan F-12/F-13 dan perbarui `AGENTS.md`.

## 9. Rollback

- Keselamatan: kembalikan `agent.safety.ts`, `conversation.router.ts`, `conversation.parts.ts`, `conversation.service.ts` ke versi sebelumnya; tidak ada migrasi.
- Registri model: skrip hanya menambah baris `RESEARCH_ONLY`; hapus baris atau set `DEPRECATED` lewat `set-model-status.ts`.
- `CONSENT_REQUIRED` 403: klien membaca `code`, jadi rollback ke 409 tidak memengaruhi aplikasi.
- Tidak ada migrasi basis data di fase ini.
