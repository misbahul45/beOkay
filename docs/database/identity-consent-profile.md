# Database — Identitas, Persetujuan, dan Profil

Migrasi: `server/prisma/migrations/20261107222128_identity_profile_consent`. Berfungsi sebagai Data Dictionary untuk subset ini.
Tabel milik Better Auth (`users`, `sessions`, `accounts`, `verifications`) tidak diubah: dibuat oleh `auth_init`, dikelola oleh pustaka.

## Konvensi
PK `UUID` (`gen_random_uuid()`), waktu `TIMESTAMPTZ`, kolom `snake_case`, nilai tidak diketahui `NULL`. Semua tabel di bawah punya FK ke `users(id)` dan semua query dibatasi `user_id` dari sesi.

## Relasi
```
users 1──0..1 user_profiles
users 1──0..1 health_profiles
users 1──0..1 user_settings
users 1──0..1 onboarding_progress
users 1──0..* consent_records
users 1──0..* audit_events   (ON DELETE SET NULL)
```
Semua FK lain `ON DELETE CASCADE` (penghapusan akun menghapus datanya).

## Tabel

### `user_profiles`
| Kolom | Tipe | Catatan |
|---|---|---|
| `id` | uuid PK | |
| `user_id` | uuid UNIQUE FK | satu profil per pengguna |
| `birth_year` | smallint NULL | CHECK 1900–2100; validasi app: tahun ini − 120 s.d. tahun ini |
| `created_at`, `updated_at` | timestamptz | |

Nama tampilan **tidak** disimpan di sini: sumber tunggalnya `users.name` (Better Auth), diubah lewat `auth.api.updateUser`.
Keberadaan baris = langkah "profil pribadi" selesai.

### `health_profiles`
| Kolom | Tipe | Aturan |
|---|---|---|
| `user_id` | uuid UNIQUE FK | |
| `diagnosis_status` | text NOT NULL | `diagnosed`, `not_diagnosed`, `unknown`, `undisclosed` |
| `diabetes_type` | text NULL | `type_2`, `type_1`, `other`, `unknown` |
| `diagnosed_year` | smallint NULL | 1900–2100 |
| `treatment_context` | text[] | subset dari `oral_medication`, `insulin`, `lifestyle`, `none`, `undisclosed` (tanpa dosis) |
| `data_source` | text | hanya `user_reported`. Tidak ada klaim verifikasi klinis |
| `eligibility_status` | text | `eligible`, `needs_review`, `unknown`; dihitung deterministik oleh server |

Invarian CHECK `health_profiles_details_require_diagnosis`: `diabetes_type` dan `diagnosed_year` hanya boleh terisi bila `diagnosis_status = 'diagnosed'`.
Aturan kelayakan: `unknown`/`undisclosed` → `unknown`; terdiagnosis + `type_2` + usia ≥ 18 (dari `birth_year`) → `eligible`; selainnya → `needs_review`. Ini penanda kecocokan produk, bukan diagnosis, dan dihitung ulang saat `birth_year` berubah.

### `user_settings`
`user_id` PK. `locale` (`id-ID` default; DB mengizinkan `en-US`, API baru menerima `id-ID`), `timezone` (default `Asia/Jakarta`, divalidasi IANA di server), `glucose_unit` (`mg/dL` default | `mmol/L`), `text_size` (`system`/`large`/`extra_large`), `reduce_motion` (bool).
Unit glukosa hanya mengatur tampilan; pengukuran sumber tidak ditulis ulang. Baris baru dibuat saat pengguna menyimpan preferensi (menandai langkah selesai); tanpa baris, API mengembalikan default dengan `isDefault: true`.

### `consent_records`
Riwayat, bukan boolean. Satu baris per pemberian.
| Kolom | Catatan |
|---|---|
| `purpose` | `health_data_processing` (wajib), `descriptive_summaries` (wajib), `product_analytics` (opsional) |
| `policy_version` | versi kebijakan saat diberikan |
| `granted_at`, `withdrawn_at` | `withdrawn_at >= granted_at` (CHECK) |
| `source` | `onboarding`, `settings`, `api` |

Partial unique index `consent_records_one_active_per_purpose (user_id, purpose) WHERE withdrawn_at IS NULL`: paling banyak satu persetujuan aktif per tujuan, sehingga tidak ada balapan ganda. Memberi persetujuan pada versi baru menutup baris lama (`withdrawn_at`, tercatat `consent_superseded` di audit) dan membuat baris baru. Menarik persetujuan tidak menghapus baris.

### `onboarding_progress`
`user_id` PK, `intro_seen_at`, `completed_at`, `version` (kontrol konkurensi optimistik, CHECK ≥ 0). **Status onboarding tidak disimpan**: diturunkan dari data nyata (lihat bagian status), supaya tidak bisa melenceng dari kenyataan.

### `audit_events`
`event_type`, `metadata` JSONB, `occurred_at`. Hanya nama field dan tujuan, **tidak pernah nilai kesehatan**. Tipe: `consent_granted`, `consent_superseded`, `consent_withdrawn`, `profile_updated`, `health_profile_updated`, `preferences_updated`, `onboarding_completed`.

## Status onboarding (diturunkan)
Urutan prioritas: `COMPLETED` (ada `completed_at`) → `EMAIL_VERIFICATION_PENDING` → `NOT_STARTED` (belum ada langkah dan intro belum dilihat) → `CONSENT_PENDING` → `PERSONAL_PROFILE_PENDING` → `HEALTH_PROFILE_PENDING` → `PREFERENCES_PENDING` → `READY_TO_COMPLETE`.
`READY_TO_COMPLETE` ditambahkan di luar daftar prompt: semua langkah selesai tetapi belum dikonfirmasi. Setelah selesai, penarikan persetujuan wajib memunculkan `requiresConsentReview: true`, bukan membuka ulang onboarding.

## Index
`user_profiles(user_id)` dan `health_profiles(user_id)` unik; `consent_records(user_id, purpose, granted_at DESC)`; `audit_events(user_id, occurred_at DESC)`.

## Migrasi dan drift
Diverifikasi pada DB kosong (`migrate deploy`) dan `prisma migrate diff`. CHECK dan partial index tidak dianggap drift. Satu-satunya sisa diff adalah noise kosmetik `gen_random_uuid()` vs `pg_catalog.gen_random_uuid()` pada empat tabel auth (sudah ada sebelumnya). Model `Users` memuat baris relasi balik yang ditambahkan manual; `auth:generate` bisa menimpanya.
