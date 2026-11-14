class SignalStatus {
  SignalStatus.fromJson(Map<String, dynamic> j)
    : signal = j['signal'] as String,
      days = (j['days'] as num?)?.toInt() ?? 14,
      observedDays = (j['observedDays'] as num?)?.toInt() ?? 0,
      coverage = (j['coverage'] as num?)?.toDouble() ?? 0,
      conflicts =
          (((j['statusCounts'] as Map?)?['CONFLICT']) as num?)?.toInt() ?? 0,
      reliable = j['reliable'] == true;
  final String signal;
  final int days, observedDays, conflicts;
  final double coverage;
  final bool reliable;

  String get label => switch (signal) {
    'steps' => 'Langkah',
    'sleep' => 'Tidur',
    'workouts' => 'Latihan',
    'heart_rate' => 'Detak jantung',
    _ => signal,
  };
}

enum WatchVerification { notVerified, sourceDetected, hardwareVerified }

WatchVerification watchVerificationFrom(String? wire) => switch (wire) {
  'WATCH_SOURCE_DETECTED' => WatchVerification.sourceDetected,
  'WATCH_HARDWARE_VERIFIED' => WatchVerification.hardwareVerified,
  _ => WatchVerification.notVerified,
};

class SourceApplication {
  const SourceApplication(this.dataOrigin, this.provenance);
  final String dataOrigin;
  final String provenance;
}

class DeviceStatus {
  DeviceStatus.fromJson(Map<String, dynamic> j)
    : signals = [
        for (final s in (j['signals'] as List? ?? const []))
          SignalStatus.fromJson(s as Map<String, dynamic>),
      ],
      origins = [
        for (final o in (j['origins'] as List? ?? const [])) o as String,
      ],
      sourceApplications = [
        for (final s in (j['sourceApplications'] as List? ?? const []))
          SourceApplication(
            (s as Map)['dataOrigin'] as String,
            s['provenance'] as String,
          ),
      ],
      detectedDeviceTypes = [
        for (final t in (j['detectedDeviceTypes'] as List? ?? const []))
          t as String,
      ],
      usedForCoaching = j['usedForCoaching'] == true,
      simulated = j['simulated'] == true,
      watch = watchVerificationFrom(j['watchVerification'] as String?),
      syncState = (j['syncState'] as String?) ?? 'NEVER_SYNCED',
      permissionState = (j['permissionState'] as String?) ?? 'UNKNOWN',
      lastSuccessfulSyncAt = DateTime.tryParse(
        (j['lastSuccessfulSyncAt'] as String?) ?? '',
      ),
      lastSyncAttemptAt = DateTime.tryParse(
        (j['lastSyncAttemptAt'] as String?) ?? '',
      ),
      lastDataAt = DateTime.tryParse((j['lastDataAt'] as String?) ?? ''),
      lastSync = {
        for (final e in ((j['lastSyncAt'] as Map?) ?? const {}).entries)
          e.key as String: DateTime.tryParse((e.value as String?) ?? ''),
      },
      notice = (j['notice'] as String?) ?? '',
      connectionNotice = (j['connectionNotice'] as String?) ?? '';
  final List<SignalStatus> signals;
  final List<String> origins, detectedDeviceTypes;
  final List<SourceApplication> sourceApplications;
  final bool usedForCoaching, simulated;
  final WatchVerification watch;
  final String syncState, permissionState;
  final DateTime? lastSuccessfulSyncAt, lastSyncAttemptAt, lastDataAt;
  final Map<String, DateTime?> lastSync;
  final String notice, connectionNotice;

  bool get hasAnyData => signals.any((s) => s.observedDays > 0);
}

String originLabel(String origin) => switch (origin) {
  'com.google.android.apps.fitness' => 'Google Fit',
  'com.sec.android.app.shealth' => 'Samsung Health',
  'com.samsung.android.wear.shealth' => 'Samsung Health (jam tangan)',
  'com.fitbit.FitbitMobile' => 'Fitbit',
  'com.garmin.android.apps.connectmobile' => 'Garmin Connect',
  'com.xiaomi.wearable' => 'Mi Fitness',
  'com.huawei.health' => 'Huawei Health',
  'beokay.simulator' || 'beokay.simulator.phone' => 'Simulasi beOkay',
  _ => origin,
};

String provenanceLabel(String provenance) => switch (provenance) {
  'WATCH_RECORDED' => 'Jam tangan',
  'PHONE_RECORDED' => 'Ponsel',
  'OTHER_DEVICE' => 'Perangkat lain',
  'USER_ENTERED' => 'Diketik pengguna',
  'SIMULATED' => 'Simulasi',
  _ => 'Asal perangkat belum diketahui',
};
