# API — beOkay

Pembaruan Slice 2: [Nutrition API](nutrition.md) menambahkan personal food catalog, meal create/read/correct/archive/restore, revisions, meal-only timeline dan daily Nutrition summary. Today sekarang memuat `nutrition` nyata dan metric nutrition AVAILABLE. Contoh Today Foundation di bawah adalah kontrak tahap awal; domain selain Nutrition tetap belum tersedia.

## Today Foundation

`GET /api/me/today`: sesi Better Auth verified; consent current `health_data_processing` dan `descriptive_summaries` wajib. Identitas selalu dari sesi, tanpa body/parameter userId. Respons `no-store`, request ID dan error wrapper existing.

```json
{
  "displayName": "Nama pengguna",
  "timezone": "Asia/Jakarta",
  "glucoseUnit": "mg/dL",
  "date": "2026-11-09",
  "greeting": "Selamat pagi",
  "generatedAt": "2026-11-09T02:00:00.000Z",
  "computationVersion": "today-foundation-v1",
  "analyticsState": "NOT_AVAILABLE",
  "metrics": [
    { "domain": "glucose", "availability": "NOT_IMPLEMENTED", "value": null },
    { "domain": "nutrition", "availability": "NOT_IMPLEMENTED", "value": null },
    { "domain": "activity", "availability": "NOT_IMPLEMENTED", "value": null },
    { "domain": "medication", "availability": "NOT_IMPLEMENTED", "value": null }
  ],
  "goals": { "availability": "NOT_IMPLEMENTED", "items": [] },
  "timeline": { "availability": "NOT_IMPLEMENTED", "items": [] }
}
```

Contoh bersifat sintetis. Nilai null berarti domain belum tersedia, bukan pengukuran nol. 401 untuk sesi hilang/kedaluwarsa, 403 `CONSENT_REQUIRED` untuk consent tidak aktif, 500 generik untuk kegagalan internal. Tidak ada endpoint tracking baru pada slice ini. Koleksi Bruno: [`bruno/`](bruno/); instruksi dan hasil: [pengujian core](../testing/core-health-experience.md).

## Authentication & Personalization

Basis URL dev: `http://localhost:3000`. Semua respons API membawa `X-Request-Id` dan `Cache-Control: no-store`.
Perilaku di bawah ini diverifikasi dengan menjalankan API di stack uji terisolasi (Docker). Koleksi Bruno menyusul di tahap berikutnya.

## Format error
```json
{ "error": { "code": "CONSENT_REQUIRED", "message": "…", "requestId": "…", "details": { } } }
```
`401 UNAUTHENTICATED` · `400 VALIDATION_ERROR`/`MALFORMED_JSON` · `403 CONSENT_REQUIRED` · `409 …` · `413`/`415` · `422 …` · `500 INTERNAL_ERROR` (tanpa detail internal). `VALIDATION_ERROR` hanya memuat `path` dan `code` isian, tidak pernah nilainya.
Respons error milik Better Auth (`/api/auth/*`) memakai format bawaannya: `{ "message", "code" }`.

## Autentikasi (Better Auth 1.7.18)
Better Auth adalah satu-satunya otoritas. Endpoint asli dipakai apa adanya:

| Aksi | Endpoint |
|---|---|
| Daftar | `POST /api/auth/sign-up/email` `{name, email, password}` |
| Masuk | `POST /api/auth/sign-in/email` `{email, password}` |
| Sesi | `GET /api/auth/get-session` |
| Keluar | `POST /api/auth/sign-out` |
| Kirim ulang verifikasi | `POST /api/auth/send-verification-email` `{email}` |
| Minta reset | `POST /api/auth/request-password-reset` `{email}` |
| Reset | `POST /api/auth/reset-password` `{newPassword, token}` |
| Ganti sandi | `POST /api/auth/change-password` |
| Daftar/cabut sesi | `GET /api/auth/list-sessions`, `POST /api/auth/revoke-session`, `/revoke-other-sessions`, `/revoke-sessions` |

Aturan yang berlaku (teramati):
- Kata sandi 10–128 karakter. Pendaftaran **tidak** membuat sesi; email verifikasi dikirim. Masuk sebelum verifikasi → `403 EMAIL_NOT_VERIFIED` (`sendOnSignIn` diaktifkan untuk mengirim ulang tautan; pengiriman ulang itu belum diuji terpisah).
- Mendaftar dengan email yang sudah ada menghasilkan respons yang sama dengan email baru (`200`, tanpa token): tidak membocorkan keberadaan akun. `request-password-reset` juga seragam untuk email dikenal maupun tidak.
- Setelah reset kata sandi, semua sesi lama dicabut.
- **Sesi mobile**: plugin `bearer`. Respons `sign-in` memuat header `set-auth-token`; kirim `Authorization: Bearer <token>` pada permintaan berikutnya. Cookie `better-auth.session_token` (HttpOnly, SameSite=Lax) tetap dikeluarkan untuk klien web.
- Pemeriksaan `Origin` hanya melindungi sesi berbasis cookie; klien native tanpa cookie dan tanpa header `Origin` tetap diterima.
- Rate limit (memori, per IP, jendela 60 dtk), dikonfigurasi: sign-in 5, sign-up 5, request-password-reset 3, reset-password 5, send-verification-email 3, change-password 5, lainnya 120. Melebihi → `429`. Teruji: sign-in (percobaan ke-6 dalam semenit → 429); batas lain baru dikonfigurasi, belum diuji satu per satu.
- IP klien: dari koneksi; dari `X-Forwarded-For` hanya bila `TRUST_PROXY=true`. Header internal `x-beokay-client-ip` dari klien selalu dibuang.
- Tautan di email mengarah ke halaman server: `/auth/verified` (hasil verifikasi) dan `/auth/reset-password?token=…` (formulir; token dibaca JS lalu dihapus dari URL; CSP ketat; `Referrer-Policy: no-referrer`).

## Rute aplikasi
Semua `/api/me/*` butuh sesi valid dengan email terverifikasi. `userId` selalu dari sesi.

### Persetujuan
| Metode & rute | Keterangan |
|---|---|
| `GET /api/consent-policies/current` | Publik. `{version, effectiveDate, summary, purposes[{purpose, required, title, description, dataCategories, withdrawalEffect}]}` |
| `GET /api/me/consents` | `{policyVersion, purposes[{purpose, required, status, policyVersion, grantedAt, withdrawnAt}], history[]}`. `status`: `granted`, `withdrawn`, `not_given`, `reconsent_required` |
| `POST /api/me/consents` | `{policyVersion, purposes[], source?}`. Versi tak sesuai → `422 POLICY_VERSION_MISMATCH`. Idempoten |
| `POST /api/me/consents/withdraw` | `{purposes[]}`. Idempoten; riwayat tidak dihapus |

Tujuan: `health_data_processing` (wajib), `descriptive_summaries` (wajib), `product_analytics` (opsional, tidak pernah pra-pilih). Teks kebijakan v1.0 adalah **draf** dan wajib ditinjau pihak berwenang.

### Onboarding
| Metode & rute | Keterangan |
|---|---|
| `GET /api/me/onboarding` | `{state, emailVerified, steps[{key, done}], introSeenAt, completedAt, version, requiresConsentReview}` |
| `PATCH /api/me/onboarding` | `{introSeen: true, expectedVersion?}`. Versi tak cocok → `409 VERSION_CONFLICT` |
| `POST /api/me/onboarding/complete` | Idempoten. Langkah kurang → `409 ONBOARDING_INCOMPLETE {missingSteps}` |

### Profil pribadi
`GET /api/me/profile` → `{exists, displayName, birthYear, completeness{complete, missing[]}, createdAt, updatedAt}`.
`PATCH /api/me/profile` `{displayName?, birthYear?|null}` (minimal satu). `displayName` 1–80 karakter tanpa karakter kontrol.

### Profil kesehatan (butuh persetujuan `health_data_processing`)
`GET`, `PUT` (ganti penuh), `PATCH` (parsial) pada `/api/me/health-profile`. Isian: `diagnosisStatus`, `diabetesType`, `diagnosedYear`, `treatmentContext[]`.
Respons memuat `provenance: {source: "user_reported", clinicallyVerified: false}` dan `eligibilityStatus`.
Kesalahan khas: `422 DETAILS_REQUIRE_DIAGNOSIS`, `422 DIAGNOSIS_BEFORE_BIRTH`, `409 HEALTH_PROFILE_NOT_CREATED` (PATCH sebelum PUT), `403 CONSENT_REQUIRED`.
`PATCH` yang mengubah status dari `diagnosed` ke lainnya mengosongkan `diabetesType` dan `diagnosedYear`.

### Preferensi
`GET /api/me/preferences` → `{locale, timezone, glucoseUnit, textSize, reduceMotion, isDefault, updatedAt}`.
`PATCH` `{locale?, timezone?, glucoseUnit?, textSize?, reduceMotion?}`. `timezone` harus IANA valid; `locale` saat ini hanya `id-ID`.

## Konfigurasi (env)
`BETTER_AUTH_SECRET` (≥ 32), `BETTER_AUTH_URL`, `TRUSTED_ORIGINS`, `TRUST_PROXY`, `EMAIL_FROM`, `SMTP_HOST/PORT/SECURE/USER/PASS`, `DATABASE_URL`. Aplikasi menolak start bila konfigurasi tidak valid.
