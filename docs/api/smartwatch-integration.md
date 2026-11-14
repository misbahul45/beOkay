# API integrasi jam tangan

Semua endpoint memerlukan sesi (Bearer) dan consent `health_data_processing`. Pemilik data selalu berasal dari sesi. Contoh sintetis; `null` berarti tidak ada data, bukan nol. Koleksi Bruno: folder `21 - Smartwatch Integration` (15 permintaan).

## Preferensi impor

`GET|PATCH /api/me/device-import/preferences`. Kunci: `workouts`, `steps`, `weight`, `glucose`, `sleep`, `heartRate`, `restingHeartRate` (semua `false` bawaan). Tambahan kunci kompatibel mundur.

## Impor

`POST /api/me/device-import` (maks. 64 KB):

```json
{
  "source": "health_connect",
  "steps": [{ "localDate": "2026-11-14", "steps": 6240, "dataOrigin": "com.example.src" }],
  "heartRate": [{ "bucketStart": "2026-11-14T08:00:00Z", "bpmMin": 62, "bpmMax": 91, "bpmAvg": 74.5, "sampleCount": 5, "dataOrigin": "com.example.src", "recordingMethod": "automatic", "device": "watch" }],
  "restingHeartRate": [{ "externalId": "hc-rhr-1", "measuredAt": "2026-11-14T06:00:00Z", "bpm": 60 }],
  "sleep": [{ "externalId": "hc-s-1", "startedAt": "...", "endedAt": "...", "device": "watch" }],
  "weights": [], "glucose": []
}
```

- `source`: `health_connect` atau `simulated` (hanya lingkungan dev/uji).
- Batas: `steps` 62, `heartRate` 200, `restingHeartRate` 62, `sleep` 62, `weights` 100, `glucose` 300. `heartRate.bucketStart` harus sejajar 5 menit UTC dan tidak di masa depan.
- `device`: `watch|phone|ring|scale|chest_strap|fitness_band|head_mounted|unknown`. `recordingMethod`: `automatic|active|manual|unknown`.

Respons: `{ source, simulated, preferences, steps: {upserted, unchanged, rejected}, weights|glucose|sleep|heartRate|restingHeartRate: { results[], created, updated, duplicate, unchanged, rejected, needsReview } }`.

Arti hasil per rekaman: `CREATED`; `UPDATED` (revisi, mis. tidur difinalkan atau bucket lebih lengkap); `DUPLICATE` (identik dengan yang tersimpan, atau tergantikan dalam permintaan yang sama); `UNCHANGED` (revisi lebih lama diabaikan, `reason: OLDER_REVISION`); `REJECTED` dengan `reason`:

`DEVICE_TYPE_DISABLED`, `HEART_RATE_OUT_OF_DOMAIN`, `BUCKET_NOT_ALIGNED`, `BUCKET_INCONSISTENT`, `SAMPLE_COUNT_INVALID`, `SLEEP_DURATION_OUT_OF_RANGE`, `GLUCOSE_VALUE_OUT_OF_DOMAIN`, `SIMULATED_NOT_SUPPORTED`. `needsReview: true` menandai nilai tidak lazim (bukan penolakan).

Kesalahan permintaan: `401` tanpa sesi, `403 CONSENT_REQUIRED`, `403 SIMULATION_DISABLED`, `400 VALIDATION_ERROR` (format/bidang asing/jumlah melebihi batas), `413 PAYLOAD_TOO_LARGE`. Batch sebagian tidak membatalkan rekaman valid.

`POST /api/me/activities/import` menerima `source: simulated` dengan penjaga yang sama; `device` dan `recordingMethod` kini dikirim klien.

## Detak jantung

`GET /api/me/heart-rate?days=7|14|30`: `series[]` per hari lokal (`observedBuckets`, `sampleCount`, `coverage`, `minimum|maximum|average|restingHeartRate` atau `null` bila sampel < 3, `needsReview`, `insufficient`), `latest` (rata-rata jendela 5 menit terakhir, bukan sampel tunggal), `restingLatest`, `freshness` (`NO_DATA|FRESH|STALE` 48 jam), `simulated`, `methodology`, `notice`.

`GET /api/me/heart-rate/day?date=YYYY-MM-DD`: `summary`, `buckets[]` (`start,min,max,avg,sampleCount,dataOrigin,needsReview,simulated`), `resting[]`. Tanggal masa depan: `400 DATE_IN_FUTURE`.

## Checkpoint sinkron

`PUT /api/me/device-sync/checkpoints` `{ source?, metric, outcome: attempt|success|failure, errorCode?, cursor? }` (`errorCode` hanya untuk `failure`, pola `[A-Z0-9_]{1,60}`). `success` memajukan kursor dan menghapus galat; `failure` mempertahankan kursor terakhir. `GET` mendaftar checkpoint. Metrik: `steps, heart_rate, resting_heart_rate, sleep, workouts, weight, glucose`.

## Status dan Today

`GET /api/me/devices/status` mempertahankan `signals`, `origins`, `lastSyncAt`, `usedForCoaching`, `notice`, dan menambah: `permissions` (+`heartRate`,`restingHeartRate`), `enabledMetrics`, `lastSyncAttemptAt`, `lastSuccessfulSyncAt`, `lastDataAt`, `syncState` (`IMPORT_DISABLED|SYNC_FAILED|NEVER_SYNCED|SYNC_STALE|OK`), `healthConnectAvailability` dan `permissionState` (dilaporkan klien lewat kode galat checkpoint, `UNKNOWN` bila tidak ada), `metricFreshness[]`, `metricQuality`, `sourceCoverage[]`, `sourceApplications[]` (+provenans), `detectedDeviceTypes`, `provenance` (hitungan per kelas), `watchVerification` (`WATCH_NOT_VERIFIED|WATCH_SOURCE_DETECTED`), `simulated`, `connectionNotice`. Sinyal `heart_rate` ditambahkan di `signals` dan `days`.

`GET /api/me/devices/today`: untuk `steps`, `heartRate`, `sleep`, `activity`: `availability` (`HAS_DATA|NO_DATA|NOT_ENABLED|PERMISSION_REQUIRED|STALE_DATA`) dan `value` (atau `null`). Tidak pernah mengisi nol.

## Ekspor dan penghapusan

`GET /api/me/export` memuat `wearableHeartRateBuckets`, `wearableRestingHeartRates`, `deviceSyncCheckpoints`. Penghapusan akun menghapus semuanya (`ON DELETE CASCADE`).
