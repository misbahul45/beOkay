# Health Tracking Schema — status Slice 1

Pembaruan Slice 4: migration20261108130338_activity menambah activity_sessions dan activity_id pada record_revisions. [Data dictionary Activity](activity-schema.md). Migrasi hanya diterapkan pada database uji, bukan dev/produksi.

Pembaruan Slice 3: migration `20261108110400_glucose` menambahkan glucose_observations dan memperluas record_revisions dengan sumber eksklusif meal/glucose. [Data dictionary Glucose](glucose-schema.md). Tidak membuat daily/weekly summaries, activity, medication, goals atau sync tables pada slice ini.

Pembaruan Slice 2: migration `20261108070202_nutrition` menambahkan food_catalog, meal_logs, meal_items dan record_revisions. [Data dictionary dan relasi Nutrition](nutrition-schema.md). Pernyataan tanpa tabel baru di bawah adalah status historis Slice 1.

Tidak ada migrasi, tabel, index atau model Prisma baru dalam Today Foundation. Sumber identitas tetap Better Auth `Users` UUID, nama dari `users.name`; preferensi dari `user_settings`; consent dari `consent_records`. Profil dan preferensi dibaca melalui service existing dengan session userId.

`food_catalog`, `meal_logs`, `meal_items`, `glucose_observations`, `activity_sessions`, regimen/schedule/intake, goals/checkins, daily/weekly summaries, sync operations, revisions dan outbox belum dibuat. Daftar tersebut adalah rencana per slice, bukan skema yang diterapkan.

Slice Nutrition berikutnya perlu data dictionary, physical relations, Screen Specification dan UI/API matrix untuk kebutuhan slice; UUID PK, FK ke Users, NUMERIC, timestamptz, snake_case, CHECK constraints, user/time index, original event/record time, snapshot nutrition dan revision policy. Buat dan verifikasi migrasi hanya pada PostgreSQL uji terisolasi, bukan dev/produksi.
