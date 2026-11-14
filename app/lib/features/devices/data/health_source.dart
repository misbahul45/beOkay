import '../../activity/data/device_activity_source.dart' show DeviceSession;

enum WearableMetric {
  steps,
  heartRate,
  restingHeartRate,
  workouts,
  sleep,
  weight,
  glucose,
}

extension WearableMetricInfo on WearableMetric {
  String get prefKey => name;

  String get checkpointKey => switch (this) {
    WearableMetric.heartRate => 'heart_rate',
    WearableMetric.restingHeartRate => 'resting_heart_rate',
    _ => name,
  };

  String get label => switch (this) {
    WearableMetric.steps => 'Langkah',
    WearableMetric.heartRate => 'Detak jantung',
    WearableMetric.restingHeartRate => 'Detak jantung istirahat',
    WearableMetric.workouts => 'Aktivitas olahraga',
    WearableMetric.sleep => 'Tidur',
    WearableMetric.weight => 'Berat badan',
    WearableMetric.glucose => 'Glukosa',
  };

  String get detail => switch (this) {
    WearableMetric.steps => 'Total langkah per hari untuk tujuan langkah',
    WearableMetric.heartRate =>
      'Ringkasan per 5 menit (terendah, rata-rata, tertinggi) dari sensor yang menulis ke Health Connect',
    WearableMetric.restingHeartRate =>
      'Detak jantung istirahat bila perangkat atau aplikasinya mengirimkannya',
    WearableMetric.workouts =>
      'Sesi dari jam tangan atau aplikasi olahraga. Health Connect meminta juga izin langkah, jarak, dan kalori total agar sesi bisa dibaca; kalori tidak disimpan',
    WearableMetric.sleep => 'Jam tidur dan bangun, tanpa tahap tidur',
    WearableMetric.weight => 'Dari timbangan pintar atau aplikasi lain',
    WearableMetric.glucose => 'Dari glukometer yang menulis ke Health Connect',
  };

  bool get sensitive =>
      this == WearableMetric.glucose || this == WearableMetric.weight;
}

const unsupportedMetricLabels = <String>[
  'Energi aktif',
  'Saturasi oksigen',
  'Variabilitas detak jantung',
];

enum HealthPlatformState {
  unsupportedPlatform,
  healthConnectUnavailable,
  installRequired,
  available,
}

class SourceCapabilities {
  const SourceCapabilities({
    required this.platform,
    this.backgroundRead = false,
    this.historyRead = false,
  });
  final HealthPlatformState platform;
  final bool backgroundRead;
  final bool historyRead;
  bool get available => platform == HealthPlatformState.available;
}

class RawMeasurement {
  const RawMeasurement({
    required this.id,
    required this.metric,
    required this.value,
    required this.unit,
    required this.startTime,
    required this.endTime,
    this.origin,
    this.recordingMethod,
    this.deviceType,
    this.deviceManufacturer,
    this.deviceModel,
    this.isSimulated = false,
  });
  final String id;
  final WearableMetric metric;
  final num value;
  final String unit;
  final DateTime startTime, endTime;
  final String? origin;
  final String? recordingMethod;
  final String? deviceType;
  final String? deviceManufacturer;
  final String? deviceModel;
  final bool isSimulated;
}

class HealthReadRequest {
  const HealthReadRequest({
    required this.metrics,
    required this.from,
    required this.to,
    this.stepsDays = 14,
  });
  final Set<WearableMetric> metrics;
  final DateTime from, to;
  final int stepsDays;
}

class HealthReadResult {
  const HealthReadResult({
    this.measurements = const [],
    this.workouts = const [],
    this.errors = const {},
  });
  final List<RawMeasurement> measurements;
  final List<DeviceSession> workouts;
  final Map<WearableMetric, String> errors;
}

abstract interface class HealthDataSource {
  String get sourceKey;
  bool get isSimulated;
  Future<SourceCapabilities> capabilities();
  Future<bool> hasAccess(WearableMetric metric);
  Future<bool> requestAccess(WearableMetric metric);
  Future<HealthReadResult> read(HealthReadRequest request);
}

abstract interface class DeviceMetadataBridge {
  Future<Map<String, DeviceMetadata>> lookup(
    Set<WearableMetric> metrics,
    DateTime from,
    DateTime to,
  );
}

class DeviceMetadata {
  const DeviceMetadata({this.type, this.manufacturer, this.model});
  final String? type;
  final String? manufacturer;
  final String? model;
}

class NoDeviceMetadata implements DeviceMetadataBridge {
  const NoDeviceMetadata();
  @override
  Future<Map<String, DeviceMetadata>> lookup(
    Set<WearableMetric> metrics,
    DateTime from,
    DateTime to,
  ) async => const {};
}
