# Health Tracking Schema — status Slice 1

Tidak ada migrasi, tabel, index atau model Prisma baru dalam Today Foundation. Sumber identitas tetap Better Auth `Users` UUID, nama dari `users.name`; preferensi dari `user_settings`; consent dari `consent_records`. Profil dan preferensi dibaca melalui service existing dengan session userId.

`food_catalog`, `meal_logs`, `meal_items`, `glucose_observations`, `activity_sessions`, regimen/schedule/intake, goals/checkins, daily/weekly summaries, sync operations, revisions dan outbox belum dibuat. Daftar tersebut adalah rencana per slice, bukan skema yang diterapkan.

Slice Nutrition berikutnya perlu data dictionary, physical relations, Screen Specification dan UI/API matrix untuk kebutuhan slice; UUID PK, FK ke Users, NUMERIC, timestamptz, snake_case, CHECK constraints, user/time index, original event/record time, snapshot nutrition dan revision policy. Buat dan verifikasi migrasi hanya pada PostgreSQL uji terisolasi, bukan dev/produksi.
