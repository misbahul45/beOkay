# Audit integrasi jam tangan (sebelum implementasi)

Tanggal: 14 November 2026. Dasar: kode di repositori pada commit `9ccbeab`, paket `health` 13.3.2 terpasang, dokumen 4.0. Tidak ada klaim perangkat nyata.

## 1. Ringkasan

Jalur data jam tangan **tidak langsung**: jam tangan → aplikasi vendor → Health Connect → beOkay. Pada awal audit jalur itu hanya sebagian ada: lima jenis data dibaca, sinkron hanya manual, tidak ada detak jantung, dan asal data tidak bisa membedakan jam tangan dari ponsel. Tidak ada satu pun uji di perangkat nyata (`adb devices` kosong; laporan 4.0 menandai C13 `UNVERIFIED`).

## 2. Temuan klien (Flutter)

| Kemampuan | Implementasi awal | Bukti | Masalah | Perubahan yang diperlukan |
|---|---|---|---|---|
| Jenis data yang dibaca | langkah, berat, glukosa, tidur, sesi olahraga | `health_signals.dart`, `device_activity_source.dart` | tidak ada detak jantung/istirahat | tambah `HEART_RATE`, `RESTING_HEART_RATE` |
| Pembaca Health Connect | dua pembaca terpisah (`HealthConnectSignals`, `HealthConnectSource`) | dua kelas, dua alur izin | duplikasi, perilaku bisa berbeda | satu adapter `HealthConnectDataSource` |
| Izin | per jenis, diminta saat saklar dinyalakan | `devices_screen.dart` | pencabutan dari pengaturan sistem tidak terdeteksi | cek `hasAccess` tiap sinkron, kode `PERMISSION_REVOKED` |
| Pemicu sinkron | hanya tombol | `syncDeviceSignals` dipanggil dari satu tombol | data cepat basi (STALE setelah 48 jam) | resume, timer aktif 15 menit, backoff |
| Latar belakang | tidak ada | tidak ada `workmanager`, tanpa `READ_HEALTH_DATA_IN_BACKGROUND` | tidak ada sinkron saat app tertutup | **tidak diimplementasikan** (lihat laporan) |
| Idempotensi | server idempoten per `externalId` | `device-import.service.ts` | revisi dari vendor dibuang (`DUPLICATE`) | upsert bertingkat, hasil `updated` |
| Zona waktu | hari lokal dari zona ponsel | `isoDate(start)` | beda zona saat bepergian | didokumentasikan sebagai batasan |
| Nol vs hilang | langkah null bila tak ada | `readSteps` | sudah benar | dipertahankan, diperluas ke semua metrik |
| Ponsel vs jam tangan | tidak bisa dibedakan | paket `health` hanya memberi `source_name` dan `recording_method` | `deviceType` tidak pernah dikirim | jembatan Kotlin sempit membaca `metadata.device` |
| Asal data | `sourceId` (nama paket) | `originLabel` menebak "jam tangan" dari nama paket | tebakan, bukan bukti | status jam tangan hanya naik dari metadata perangkat |
| Akun berganti | dilindungi `AccountScopedRepository` | `write()` | tidak ada perlindungan untuk sinkron panjang | cek akun di tiap batch |
| Gagal sinkron | tidak ada keadaan pulih | tidak ada checkpoint | harus baca ulang manual | kursor per metrik, outbox terbatas |
| Kompatibilitas paket | `health` 13.3.2 menyediakan `getChangesToken`/`getChanges`, tipe detak jantung | kode paket | audit awal sempat menyatakan sebaliknya (keliru) | dicatat; sinkron memakai jendela bergulir, bukan change token |

## 3. Temuan server

| Kemampuan | Awal | Masalah | Perubahan |
|---|---|---|---|
| Tabel | `daily_steps`, `sleep_sessions`, `vital_measurements`, `glucose_observations`, `activity_sessions` | tidak ada detak jantung, tidak ada checkpoint | tiga tabel baru (additif) |
| Provenans | `dataOrigin` ada; `recordingMethod` disimpan tapi tidak dipakai; `device` diterima tapi tidak pernah dikirim | `activeMinutesDevice` menghitung semua sumber non-manual, termasuk ketikan manual di aplikasi lain, dengan bobot 1,0 di `score-v2` | `recordingMethod=manual` dihitung manual, versi proyeksi `daily-facts-v2` |
| Revisi | create-only untuk tidur/berat/glukosa/latihan | sesi tidur yang difinalkan vendor tidak pernah diperbarui | tidur di-upsert; bucket detak jantung monoton menurut `sampleCount` |
| Status perangkat | izin, sinkron terakhir, 14 hari per sinyal | tidak memisahkan izin, sinkron, kesegaran, verifikasi jam tangan | bidang status diperluas, kompatibel mundur |
| Konsumen | proyeksi, koreksi, tujuan, FHIR | tidak ada pemisahan data simulasi | sumber `simulated` dikecualikan dari semua konsumen |
| Produksi | semua sumber diterima | tidak ada penjaga simulasi | penjaga di server (`DEVICE_SIMULATION_ENABLED` dan `NODE_ENV`) |

## 4. Penilaian risiko

Tingkat: T tinggi, S sedang, R rendah. Kemungkinan: T/S/R.

| Risiko | Dampak | Kemungkinan | Mitigasi di implementasi | Sisa risiko |
|---|---|---|---|---|
| Langkah ganda | T | S | agregat Health Connect tanpa entri manual; satu baris per hari per sumber | S: asal data per langkah tidak terlihat |
| Latihan ganda dua penyedia | S | T | sesi bertabrakan → `needs_review`, tidak dihitung | R |
| Impor ulang | S | T | idempoten per kunci logis, uji replay | R |
| Zona waktu salah | S | S | agregasi hari memakai zona profil di server; hari langkah memakai zona ponsel | S |
| Satuan salah | T | R | bpm bilangan bulat 20–300, domain dicek di klien dan server | R |
| Timestamp tidak valid | S | S | validasi zod dan penolakan per rekaman | R |
| Konflik sinkron / revisi lama menimpa baru | S | S | bucket hanya naik menurut `sampleCount`; tidur diperbarui | S: tidak ada `lastModifiedTime` |
| Consent dicabut | T | S | server menolak 403, klien menghapus outbox | R |
| Health Connect tidak ada / izin ditolak | R | T | keadaan eksplisit, aplikasi tetap berfungsi manual | R |
| Data satu pengguna muncul di akun lain | T | R | kunci outbox dan kursor per akun, cek akun per batch, semua query dibatasi `user_id` | R |
| Data simulasi dianggap nyata | T | S | sumber `simulated`, penjaga server, banner, filter konsumen | R |
| Data sensitif di log | T | R | tidak ada nilai di log; hanya hitungan | R |
| Baterai | S | S | tanpa polling detik; timer 15 menit hanya saat app aktif | S: latar belakang belum ada |
| Tugas latar gagal berulang | S | R | tidak ada tugas latar | tidak berlaku |
| Penghapusan di sumber tidak tersinkron | S | S | **tidak ditangani** | S |
