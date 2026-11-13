import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../data/health_signals.dart';

final healthSignalsSourceProvider = Provider<HealthSignalsSource?>(
  (ref) => Platform.isAndroid ? HealthConnectSignals() : null,
);

final deviceImportRepositoryProvider = Provider<DeviceImportRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final id = auth is AuthAuthenticated ? auth.user.id : null;
  return DeviceImportRepository(
    ref.watch(apiClientProvider),
    isCurrentAccount: () {
      if (!ref.mounted) return false;
      final current = ref.read(authControllerProvider);
      return id != null &&
          current is AuthAuthenticated &&
          current.user.id == id;
    },
  );
});

final devicePreferencesProvider =
    FutureProvider.autoDispose<Map<SignalType, bool>>(
      (ref) => ref.watch(deviceImportRepositoryProvider).preferences(),
    );

class StepsSummary {
  StepsSummary.fromJson(Map<String, dynamic> j)
    : daysWithData = (j['daysWithData'] as num).toInt(),
      median = j['medianSteps'] as num?,
      today = ((j['series'] as List).last as Map)['steps'] as int?;
  final int daysWithData;
  final num? median;
  final int? today;
}

final stepsSummaryProvider = FutureProvider.autoDispose<StepsSummary?>((
  ref,
) async {
  if (ref.watch(authControllerProvider) is! AuthAuthenticated) return null;
  try {
    return StepsSummary.fromJson(
      (await ref.watch(apiClientProvider).get('/api/me/steps?days=7')).object,
    );
  } catch (_) {
    return null;
  }
});

Future<DeviceImportResult> syncDeviceSignals(
  HealthSignalsSource source,
  DeviceImportRepository repo,
  Map<SignalType, bool> prefs, {
  int days = 14,
}) async {
  final now = DateTime.now();
  final from = now.subtract(Duration(days: days));
  Future<bool> ok(SignalType t) async =>
      prefs[t] == true && await source.hasAccess(t);
  return repo.send(
    steps: await ok(SignalType.steps) ? await source.readSteps(days) : const [],
    weights: await ok(SignalType.weight)
        ? await source.read(SignalType.weight, from, now)
        : const [],
    glucose: await ok(SignalType.glucose)
        ? await source.read(SignalType.glucose, from, now)
        : const [],
    sleep: await ok(SignalType.sleep)
        ? await source.read(SignalType.sleep, from, now)
        : const [],
  );
}

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
    _ => signal,
  };
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
      usedForCoaching = j['usedForCoaching'] == true,
      lastSync = {
        for (final e in ((j['lastSyncAt'] as Map?) ?? const {}).entries)
          e.key as String: DateTime.tryParse((e.value as String?) ?? ''),
      },
      notice = (j['notice'] as String?) ?? '';
  final List<SignalStatus> signals;
  final List<String> origins;
  final bool usedForCoaching;
  final Map<String, DateTime?> lastSync;
  final String notice;
}

final deviceStatusProvider = FutureProvider.autoDispose<DeviceStatus?>((
  ref,
) async {
  if (ref.watch(authControllerProvider) is! AuthAuthenticated) return null;
  try {
    return DeviceStatus.fromJson(
      (await ref.watch(apiClientProvider).get('/api/me/devices/status')).object,
    );
  } catch (_) {
    return null;
  }
});

String originLabel(String origin) => switch (origin) {
  'com.google.android.apps.fitness' => 'Google Fit',
  'com.sec.android.app.shealth' => 'Samsung Health',
  'com.samsung.android.wear.shealth' => 'Samsung Health (jam tangan)',
  'com.fitbit.FitbitMobile' => 'Fitbit',
  'com.garmin.android.apps.connectmobile' => 'Garmin Connect',
  'com.xiaomi.wearable' => 'Mi Fitness',
  'com.huawei.health' => 'Huawei Health',
  _ => origin,
};
