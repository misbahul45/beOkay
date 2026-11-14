import '../data/health_source.dart';

enum DeviceConnectionState {
  platformUnavailable,
  healthConnectUnavailable,
  notAuthorized,
  authorizedNoData,
  dataAvailable,
  syncing,
  syncFailed,
  syncStale,
  importDisabled,
}

const staleAfter = Duration(hours: 48);

DeviceConnectionState deriveConnectionState({
  required HealthPlatformState platform,
  required Set<WearableMetric> enabled,
  required Set<WearableMetric> granted,
  required bool syncing,
  required DateTime now,
  String? lastErrorCode,
  DateTime? lastSuccessAt,
  bool hasData = false,
}) {
  if (platform == HealthPlatformState.unsupportedPlatform) {
    return DeviceConnectionState.platformUnavailable;
  }
  if (platform != HealthPlatformState.available) {
    return DeviceConnectionState.healthConnectUnavailable;
  }
  if (enabled.isEmpty) return DeviceConnectionState.importDisabled;
  if (syncing) return DeviceConnectionState.syncing;
  if (enabled.intersection(granted).isEmpty) {
    return DeviceConnectionState.notAuthorized;
  }
  if (lastErrorCode != null) return DeviceConnectionState.syncFailed;
  if (!hasData) return DeviceConnectionState.authorizedNoData;
  if (lastSuccessAt == null || now.difference(lastSuccessAt) > staleAfter) {
    return DeviceConnectionState.syncStale;
  }
  return DeviceConnectionState.dataAvailable;
}

extension ConnectionStateText on DeviceConnectionState {
  String get title => switch (this) {
    DeviceConnectionState.platformUnavailable =>
      'Tidak didukung di perangkat ini',
    DeviceConnectionState.healthConnectUnavailable =>
      'Health Connect belum tersedia',
    DeviceConnectionState.notAuthorized => 'Izin belum diberikan',
    DeviceConnectionState.authorizedNoData => 'Terhubung, belum ada data',
    DeviceConnectionState.dataAvailable => 'Data tersedia',
    DeviceConnectionState.syncing => 'Sedang menyinkronkan',
    DeviceConnectionState.syncFailed => 'Sinkronisasi gagal',
    DeviceConnectionState.syncStale => 'Data sudah lama',
    DeviceConnectionState.importDisabled => 'Belum ada data yang diimpor',
  };

  String get explanation => switch (this) {
    DeviceConnectionState.platformUnavailable =>
      'Impor data perangkat hanya tersedia di Android.',
    DeviceConnectionState.healthConnectUnavailable =>
      'Health Connect belum terpasang atau perlu diperbarui. Kamu tetap bisa mencatat secara manual.',
    DeviceConnectionState.notAuthorized =>
      'Berikan izin baca di Health Connect untuk jenis data yang kamu nyalakan.',
    DeviceConnectionState.authorizedNoData =>
      'Izin sudah diberikan, tetapi Health Connect belum punya data untuk jenis ini. Ini tidak berarti ada masalah.',
    DeviceConnectionState.dataAvailable =>
      'Data terbaru dari Health Connect sudah masuk.',
    DeviceConnectionState.syncing => 'Mohon tunggu sebentar.',
    DeviceConnectionState.syncFailed =>
      'Sinkronisasi terakhir tidak berhasil. Data yang sudah ada tetap aman; coba lagi.',
    DeviceConnectionState.syncStale =>
      'Belum ada sinkronisasi berhasil dalam 2 hari. Buka aplikasi jam tangan agar datanya masuk ke Health Connect, lalu sinkronkan.',
    DeviceConnectionState.importDisabled =>
      'Nyalakan jenis data yang ingin kamu impor. Semuanya mati sampai kamu menyalakannya.',
  };
}
