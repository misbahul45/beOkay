# beOkay 3.0 — Fase 8: Ukur dan ringankan

> Tanggal: 12 November 2026. Cakupan dari [gap analysis §8](../audits/gap-analysis-2026-11-12.md): D-1, D-5, K-2, U-1, U-5, U-6, K-5, K-6, K-10, S-2, S-3.
> **Desain FigCraft belum dibuat.** MCP `figcraft` gagal tersambung sepanjang sesi (`CONNECTION_CLOSED`). Layar baru dibangun dari komponen yang sudah ada (`form_kit`, `detail_kit`, `InfoCard`, `SettingsGroup`) tanpa maket pengganti; halaman FigCraft "29 — Fase 8" masih terutang.

## 1. Ringkasan

| Butir | Hasil | Status |
|---|---|---|
| D-1 analitik ber-consent | tabel `usage_events`; peristiwa server lewat kait audit, peristiwa klien lewat batch; consent ditarik = data dihapus | **selesai** |
| D-5 kanal kejadian | Pengaturan → "Laporkan masalah atau kejadian" → `incident_reports` + audit + surel pemilik | **selesai**, butuh `INCIDENT_EMAIL_TO` di prod |
| K-2 jangkar klinis | berat, tinggi, lingkar pinggang, tekanan darah, 9 jenis hasil lab; ringkasan deskriptif; pengingat HbA1c 90 hari | **selesai** |
| U-1 catat cepat | kartu "Sering dicatat" di Beranda dan lembar Catat, satu ketukan | **selesai** |
| U-5 umpan balik saat simpan | "Dibandingkan catatanmu" di detail glukosa dan makan | **selesai** |
| U-6 pasangan glukosa–makan | sebelum/sesudah makan di detail makan, "bukan sebab-akibat" | **selesai** |
| K-5 tujuan adaptif | `coach-rules-v2`: naik (persentil 60, ≤ +10% atau +1) dan turun, selalu opt-in | **selesai** |
| K-6 problem solving | `strategy-catalog-v1`, rencana 7 hari dari strategi, ditinjau minggu berikutnya | **selesai**, daftar menunggu klinisi |
| K-10 nilai ekstrem di form | pesan < 70 dan ≥ 300 mg/dL saat mengetik dan di detail | **selesai**, teks menunggu klinisi |
| S-2 sakelar fitur | `feature_flags` + cache 30 dtk + `503 FEATURE_DISABLED` | **selesai** |
| S-3 retensi | pekerja harian `retention-v1` | **selesai** |

Kriteria terima fase: (1) setiap peristiwa pemakaian tercatat hanya dengan consent: **terpenuhi**, diuji termasuk penarikan consent; (2) catat-ulang satu ketukan dari Beranda: **terpenuhi**; (3) nilai ekstrem di form memberi pesan: **terpenuhi**; (4) tujuan menyesuaikan dua arah dengan log: **terpenuhi** (revisi + audit dengan `direction`); (5) semua ukuran yang ditandai "ukuran" untuk butir Fase 8 bisa dihitung dari DB: **terpenuhi kecuali** SUS/keterbacaan (butuh kuesioner) dan laju pencapaian tujuan 60–80% (lihat [measures.md](../research/measures.md)).

## 2. Analitik berbasis consent (D-1)

- `usage_events` hanya menyimpan jenis peristiwa, domain, `meta` dengan kunci tetap (`via`, `screen`, `durationMs`, `source`, `trigger`, `kind`, `position`, `shown`), versi aplikasi, platform, dan waktu. CHECK membatasi jenis dan domain; Zod menolak kunci lain (`{"note": "gula 250"}` → 400). Tes integrasi memeriksa bahwa nilai glukosa tidak pernah muncul di baris analitik.
- Peristiwa server (`record_created`, `suggestion_accepted/declined/offered`, `reflection_completed`, `strategy_chosen`) dibuat oleh kait `onAudit` di dalam transaksi pencatatan. Jadi replay idempoten tidak dihitung dua kali, dan rollback ikut membatalkan peristiwanya.
- Peristiwa klien (`form_saved` dengan durasi, `quick_repeat_used`, `context_viewed`, `screen_opened`, `notification_opened`) dikirim per 10 atau tiap 20 dtk, hanya bila consent analitik di aplikasi berstatus aktif; tanpa consent server tetap membalas `202 {recorded: false}`.
- Menarik consent `product_analytics` menghapus semua baris pengguna itu dalam transaksi penarikan. Ekspor JSON memuat `usageEvents`; hapus akun ikut cascade.
- Sakelar `analytics` mematikan pencatatan seluruhnya.

## 3. Jangkar klinis (K-2)

- `vital_measurements` dan `lab_results` mengikuti pola glukosa: ID dari klien, idempoten, versi, koreksi dengan alasan ke `record_revisions`, arsip, antrean luring (`vital`, `lab`).
- Batas nilai dan satuan sama di Zod, model, dan CHECK (mis. tekanan darah 40–300/20–200 mmHg, sistolik > diastolik; HbA1c 2–25 % atau 1–300 mmol/mol). Satuan tidak dikonversi.
- `GET /api/me/clinical/summary`: nilai terbaru dan sebelumnya, selisih deskriptif ("Turun 2,1 kg dari sebelumnya"). Tidak ada IMT, kategori, atau kata "normal/tinggi"; tes memeriksa tidak ada label klinis di balasan.
- Pengingat HbA1c: kartu di Beranda dan notifikasi `LAB_REMINDER` sekali per hasil yang sudah ≥ 90 hari. Pengguna yang belum pernah mencatat HbA1c tidak diganggu.
- Layar: Profil → "Ukuran & hasil lab", lembar Catat → "Ukuran & lab".

## 4. Catat cepat dan umpan balik (U-1, U-5, U-6, K-10)

- `GET /api/me/quick-record/suggestions` mengelompokkan makan 30 hari menurut isi yang sama (makanan, jumlah, satuan) dan aktivitas manual menurut jenis/durasi/intensitas. Ketukan "Ulangi" mengirim templat ke `POST /api/me/meals|activities` dengan ID baru dan waktu sekarang, jadi consent, idempotensi, nilai gizi dari katalog, dan antrean luring sama dengan form. Snackbar "Tersimpan: …" dengan tombol "Lihat" dan pengumuman pembaca layar.
- Konteks glukosa: median pribadi 14 hari dengan konteks yang sama, minimal 3 catatan; kalimat netral ("Lebih rendah dari median puasa 14 harimu: 128 mg/dL dari 3 catatan."), pembacaan sebelumnya, dan catatan "bukan penilaian klinis". Catatan "perlu ditinjau" tidak dibandingkan.
- Konteks makan: karbohidrat dibandingkan dengan median kategori yang sama hanya bila semua item punya nilai karbohidrat; pasangan glukosa sebelum (−90…+10 menit) dan sesudah (+60…+180 menit, terdekat ke 2 jam) dengan selisih dan kalimat "Dua angka …, bukan sebab-akibat".
- Nilai ekstrem: setiap catatan glukosa membawa `alert` dengan ambang `GLUCOSE_LIMITS` milik Asisten. Form menampilkan pesan saat mengetik (mg/dL dan mmol/L), detail menampilkannya ulang. Penyimpanan tidak diblokir.

## 5. Tujuan adaptif dan problem solving (K-5, K-6)

- `goalAdjustments` (`coach-rules-v2`): turun seperti v1 bila < 60% target; naik bila minggu ini tercapai dan ≥ 2 dari ≤ 4 minggu terakhir tercapai. Target baru = persentil ke-60 dari minggu-minggu itu, dibatasi +10% (dibulatkan ke bawah kelipatan 5 menit) atau +1 untuk tujuan hitungan; catat makan maksimal 7. Riwayat minggu dihitung ulang dari catatan, bukan dari cache.
- Usulan tetap opt-in (sakelar di refleksi, default mati). Revisi tujuan menyimpan alasan "dinaikkan/diturunkan atas persetujuan pengguna"; audit `goal_updated` memuat `direction`, `fromTarget`, `toTarget`, `rules`.
- Problem solving: untuk setiap hambatan yang dipilih, refleksi menawarkan 2–3 strategi dari daftar tetap. Satu pilihan menjadi rencana `PROBLEM_SOLVING`/`HABIT_STEP` 7 hari yang hanya dikonfirmasi pengguna (tidak diamati otomatis, hari lewat tampil "tidak diketahui", bukan "belum terlihat"). Refleksi berikutnya menampilkan "Cara yang kamu coba" dan pengakuan "Strategi … kamu jalankan N hari".
- Teks strategi berstatus `DRAFT_NOT_CLINICALLY_REVIEWED` dan aplikasi menyebutnya. Daftar lengkap ada di [paket tinjauan klinisi §6a](../research/safety-clinical-review-packet.md).

## 6. Operasi pilot (S-2, S-3, D-5)

- Sakelar fitur: sembilan kunci. Nilai di tabel menang atas `FEATURES_DISABLED`. Cache 30 dtk, jadi mematikan fitur berlaku < 1 menit tanpa restart (diuji: komunitas dan percakapan langsung `503`, glukosa tetap 200). Beranda menyembunyikan sorotan komunitas bila mati.
- Retensi: lihat [runbook §5](../operations/runbook.md). Diuji bahwa audit lama, notifikasi lama yang sudah dibaca, dan analitik lama terhapus, sedangkan data baru dan notifikasi belum dibaca tetap.
- Laporan kejadian: kategori, pesan, izin dihubungi. Surel memuat kontak hanya bila diizinkan. Kategori "Kejadian tidak diinginkan" membalas dengan rujukan 119. 5 laporan per jam.

## 7. Pengujian

| Lapisan | Hasil |
|---|---|
| Backend `bun test` (stack uji dibuat ulang bersih) | **349/349** dalam satu putaran bersih. Baru: `tests/unit/phase8.test.ts` (8), `tests/integration/phase8.test.ts` (10), satu tes refleksi Fase 8 di `coaching.test.ts` |
| `tsc --noEmit` | bersih |
| `prisma migrate diff` | hanya drift lama (2 FK, 1 indeks unik komunitas, HNSW) dan `gen_random_uuid` auth |
| Flutter | **218/218**, `flutter analyze` bersih; baru `test/flows/phase8_test.dart` (8) |

Pengulangan suite yang sangat cepat dapat gagal di `identity` dan `account` karena batas laju pendaftaran Better Auth (F-15, sudah ada sebelum fase ini); putaran dari stack bersih hijau. Tidak diverifikasi: emulator/ponsel, surel ke kotak masuk nyata, pembaca layar sungguhan.

## 8. Yang harus dilakukan pemilik

1. Isi `INCIDENT_EMAIL_TO` di `.env.prod` dan tetapkan siapa yang membaca laporan kejadian.
2. Minta klinisi meninjau §6a paket keselamatan (pesan form glukosa, daftar strategi, alur laporan).
3. Nyalakan FigCraft (`figcraft --control 7979`) agar halaman desain Fase 8 bisa dibuat.

## 9. Rollback

Migrasi `20261112090000_p8_measure_and_lighten` hanya menambah tabel, kolom nullable, dan memperluas CHECK. Rollback kode: kembalikan berkas Fase 8; tabel baru boleh dibiarkan kosong. Mematikan perilaku tanpa rollback: `feature-flag.ts set analytics off`, `RETENTION_WORKER_ENABLED=false`.
