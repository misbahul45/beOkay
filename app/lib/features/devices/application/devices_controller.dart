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
