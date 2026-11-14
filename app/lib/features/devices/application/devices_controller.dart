import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/offline/sync_controller.dart';
import '../../../core/providers.dart';
import '../../activity/application/activity_controller.dart';
import '../../auth/application/auth_controller.dart';
import '../../clinical/application/clinical_controller.dart';
import '../../today/application/today_controller.dart';
import '../data/device_import_repository.dart';
import '../data/health_connect_source.dart';
import '../data/health_source.dart';
import '../data/simulated_source.dart';
import '../domain/connection_state.dart';
import '../domain/device_status.dart';
import '../domain/heart_rate.dart';
import 'sync_coordinator.dart';
import 'sync_store.dart';

const simulationAvailable =
    kDebugMode || bool.fromEnvironment('BEOKAY_SIMULATION');

class SimulationProfileController extends Notifier<SimulationProfile?> {
  @override
  SimulationProfile? build() => null;
  void use(SimulationProfile? profile) => state = profile;
}

final simulationProfileProvider =
    NotifierProvider<SimulationProfileController, SimulationProfile?>(
      SimulationProfileController.new,
    );

final simulatedSourceProvider = Provider<SimulatedHealthDataSource>(
  (ref) => SimulatedHealthDataSource(includeCompatibilityFixtures: true),
);

final healthDataSourceProvider = Provider<HealthDataSource?>((ref) {
  final profile = simulationAvailable
      ? ref.watch(simulationProfileProvider)
      : null;
  if (profile != null) {
    final source = ref.watch(simulatedSourceProvider);
    source.profile = profile;
    return source;
  }
  return Platform.isAndroid ? HealthConnectDataSource() : null;
});

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

final syncStoreProvider = Provider<SyncStore?>((ref) {
  final auth = ref.watch(authControllerProvider);
  if (auth is! AuthAuthenticated) return null;
  return SyncStore(ref.watch(keyValueStoreProvider), auth.user.id);
});

final devicePreferencesProvider =
    FutureProvider.autoDispose<Map<WearableMetric, bool>>(
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

final deviceStatusProvider = FutureProvider.autoDispose<DeviceStatus?>((
  ref,
) async {
  if (ref.watch(authControllerProvider) is! AuthAuthenticated) return null;
  try {
    return await ref.watch(deviceImportRepositoryProvider).status();
  } catch (_) {
    return null;
  }
});

final deviceTodayProvider = FutureProvider.autoDispose<DeviceToday?>((
  ref,
) async {
  if (ref.watch(authControllerProvider) is! AuthAuthenticated) return null;
  try {
    return DeviceToday.fromJson(
      (await ref.watch(apiClientProvider).get('/api/me/devices/today')).object,
    );
  } catch (_) {
    return null;
  }
});

final heartRateSummaryProvider = FutureProvider.autoDispose
    .family<HeartRateSummary, int>((ref, days) async {
      final json =
          (await ref
                  .watch(apiClientProvider)
                  .get('/api/me/heart-rate?days=$days'))
              .object;
      return HeartRateSummary.fromJson(json);
    });

final heartRateDayProvider = FutureProvider.autoDispose
    .family<HeartRateDayDetail, String>((ref, date) async {
      final json =
          (await ref
                  .watch(apiClientProvider)
                  .get('/api/me/heart-rate/day?date=$date'))
              .object;
      return HeartRateDayDetail.fromJson(json);
    });

class DeviceConnectionView {
  const DeviceConnectionView({
    this.loading = true,
    this.platform = HealthPlatformState.available,
    this.backgroundRead = false,
    this.prefs = const {},
    this.granted = const {},
    this.syncing = false,
    this.report,
    this.status,
    this.message,
    this.failed = false,
    this.lastErrorCode,
    this.lastSuccessAt,
  });

  final bool loading;
  final HealthPlatformState platform;
  final bool backgroundRead;
  final Map<WearableMetric, bool> prefs;
  final Set<WearableMetric> granted;
  final bool syncing, failed;
  final SyncReport? report;
  final DeviceStatus? status;
  final String? message, lastErrorCode;
  final DateTime? lastSuccessAt;

  Set<WearableMetric> get enabled => {
    for (final e in prefs.entries)
      if (e.value) e.key,
  };

  DeviceConnectionState get state => deriveConnectionState(
    platform: platform,
    enabled: enabled,
    granted: granted,
    syncing: syncing,
    now: DateTime.now(),
    lastErrorCode: lastErrorCode,
    lastSuccessAt: lastSuccessAt ?? status?.lastSuccessfulSyncAt,
    hasData: status?.hasAnyData ?? ((report?.totals.imported ?? 0) > 0),
  );

  DeviceConnectionView copyWith({
    bool? loading,
    HealthPlatformState? platform,
    bool? backgroundRead,
    Map<WearableMetric, bool>? prefs,
    Set<WearableMetric>? granted,
    bool? syncing,
    SyncReport? report,
    DeviceStatus? status,
    String? message,
    bool clearMessage = false,
    bool? failed,
    String? lastErrorCode,
    bool clearError = false,
    DateTime? lastSuccessAt,
  }) => DeviceConnectionView(
    loading: loading ?? this.loading,
    platform: platform ?? this.platform,
    backgroundRead: backgroundRead ?? this.backgroundRead,
    prefs: prefs ?? this.prefs,
    granted: granted ?? this.granted,
    syncing: syncing ?? this.syncing,
    report: report ?? this.report,
    status: status ?? this.status,
    message: clearMessage ? null : message ?? this.message,
    failed: failed ?? this.failed,
    lastErrorCode: clearError ? null : lastErrorCode ?? this.lastErrorCode,
    lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
  );
}

String describeReport(SyncReport r) {
  if (r.blockedBy != null) return messageForSyncCode(r.blockedBy!);
  final parts = <String>[];
  for (final e in r.outcomes.entries) {
    if (e.value.failed) continue;
    final x = e.value.result;
    if (e.value.skippedReason != null) continue;
    if (x.imported > 0) {
      parts.add('${e.key.label.toLowerCase()} ${x.imported}');
    }
  }
  final failures = r.outcomes.values.where((o) => o.failed).toList();
  var text = parts.isEmpty
      ? 'Tidak ada data baru dari ${r.simulated ? 'simulasi' : 'Health Connect'}.'
      : 'Diperbarui: ${parts.join(', ')}.';
  final review = r.totals.needsReview;
  if (review > 0) text += ' $review perlu diperiksa.';
  if (r.sleepConflicts > 0) {
    text +=
        ' ${r.sleepConflicts} sesi tidur dari dua sumber saling tumpang tindih.';
  }
  if (failures.isNotEmpty) {
    text +=
        ' ${failures.map((f) => '${f.metric.label}: ${messageForSyncCode(f.errorCode!)}').join(' ')}';
  }
  return text;
}

String messageForSyncCode(String code) => switch (code) {
  'HEALTH_CONNECT_UNAVAILABLE' =>
    'Health Connect belum tersedia di perangkat ini.',
  'HEALTH_CONNECT_INSTALL_REQUIRED' =>
    'Health Connect perlu dipasang atau diperbarui.',
  'PLATFORM_UNSUPPORTED' => 'Impor data perangkat hanya tersedia di Android.',
  'PERMISSION_DENIED' => 'Izin Health Connect belum diberikan.',
  'PERMISSION_REVOKED' => 'Izin Health Connect dicabut.',
  'NETWORK_UNAVAILABLE' =>
    'Tidak ada koneksi. Data disimpan di perangkat dan dikirim saat tersambung.',
  'CONSENT_REQUIRED' =>
    'Persetujuan data kesehatan ditarik. Sinkronisasi dihentikan.',
  'UNAUTHENTICATED' => 'Sesi berakhir. Masuk kembali.',
  'ACCOUNT_CHANGED' => 'Akun berganti. Sinkronisasi dibatalkan.',
  'IMPORT_DISABLED' => 'Belum ada jenis data yang dinyalakan.',
  'SIMULATION_DISABLED' => 'Server menolak data simulasi.',
  'RATE_LIMITED' => 'Terlalu sering. Coba lagi nanti.',
  'READ_FAILED' => 'Gagal membaca dari Health Connect.',
  'VALIDATION_ERROR' => 'Data ditolak server.',
  _ => 'Terjadi kendala di server.',
};

class DeviceConnectionController extends Notifier<DeviceConnectionView> {
  int _failures = 0;
  DateTime? _nextAllowed;

  @override
  DeviceConnectionView build() {
    ref.watch(authControllerProvider);
    ref.watch(healthDataSourceProvider);
    return const DeviceConnectionView();
  }

  bool get _live => ref.mounted;

  HealthDataSource? get _source => ref.read(healthDataSourceProvider);

  Future<void> refresh() async {
    final source = _source;
    if (source == null) {
      state = const DeviceConnectionView(
        loading: false,
        platform: HealthPlatformState.unsupportedPlatform,
      );
      return;
    }
    final caps = await source.capabilities();
    Map<WearableMetric, bool> prefs = state.prefs;
    String? error;
    try {
      prefs = await ref.read(deviceImportRepositoryProvider).preferences();
    } catch (e) {
      error = messageFor(e);
    }
    final granted = <WearableMetric>{};
    if (caps.available) {
      for (final e in prefs.entries) {
        if (e.value && await source.hasAccess(e.key)) granted.add(e.key);
      }
    }
    DeviceStatus? status;
    try {
      status = await ref.read(deviceImportRepositoryProvider).status();
    } catch (_) {}
    if (!_live) return;
    state = state.copyWith(
      loading: false,
      platform: caps.platform,
      backgroundRead: caps.backgroundRead,
      prefs: prefs,
      granted: granted,
      status: status,
      message: error,
      failed: error != null,
      clearMessage: error == null,
    );
  }

  Future<void> toggle(WearableMetric metric, bool on) async {
    final source = _source;
    if (source == null) return;
    state = state.copyWith(syncing: true, clearMessage: true, failed: false);
    try {
      if (on) {
        final caps = await source.capabilities();
        if (!caps.available) {
          state = state.copyWith(
            syncing: false,
            platform: caps.platform,
            failed: true,
            message: messageForSyncCode(
              caps.platform == HealthPlatformState.installRequired
                  ? 'HEALTH_CONNECT_INSTALL_REQUIRED'
                  : caps.platform == HealthPlatformState.unsupportedPlatform
                  ? 'PLATFORM_UNSUPPORTED'
                  : 'HEALTH_CONNECT_UNAVAILABLE',
            ),
          );
          return;
        }
        if (!await source.hasAccess(metric) &&
            !await source.requestAccess(metric)) {
          state = state.copyWith(
            syncing: false,
            failed: true,
            message:
                'Izin ${metric.label.toLowerCase()} belum diberikan di Health Connect.',
          );
          return;
        }
      }
      final prefs = await ref
          .read(deviceImportRepositoryProvider)
          .setPreference(metric, on);
      final granted = {...state.granted};
      on ? granted.add(metric) : granted.remove(metric);
      if (!_live) return;
      state = state.copyWith(syncing: false, prefs: prefs, granted: granted);
      ref.invalidate(devicePreferencesProvider);
      _invalidateData();
      if (on) {
        await syncNow(trigger: SyncTrigger.initialConnection);
      } else {
        state = state.copyWith(
          message:
              '${metric.label} dimatikan. Data yang sudah masuk tetap tersimpan.',
          failed: false,
        );
      }
    } catch (e) {
      if (_live) {
        state = state.copyWith(
          syncing: false,
          failed: true,
          message: messageFor(e),
        );
      }
    }
  }

  Future<void> stopAll() async {
    state = state.copyWith(syncing: true, clearMessage: true);
    try {
      final prefs = await ref
          .read(deviceImportRepositoryProvider)
          .setPreferences({for (final m in WearableMetric.values) m: false});
      if (!_live) return;
      state = state.copyWith(
        syncing: false,
        prefs: prefs,
        granted: {},
        message:
            'Sinkronisasi dihentikan. Data yang sudah masuk tetap tersimpan.',
        failed: false,
        clearError: true,
      );
      _invalidateData();
    } catch (e) {
      if (_live) {
        state = state.copyWith(
          syncing: false,
          failed: true,
          message: messageFor(e),
        );
      }
    }
  }

  Future<SyncReport?> syncNow({
    SyncTrigger trigger = SyncTrigger.manual,
  }) async {
    final coordinator = ref.read(syncCoordinatorProvider);
    if (coordinator == null) return null;
    final interactive =
        trigger == SyncTrigger.manual ||
        trigger == SyncTrigger.initialConnection;
    if (!interactive) {
      final now = DateTime.now();
      if (_nextAllowed != null && now.isBefore(_nextAllowed!)) return null;
      if (state.prefs.isEmpty) await refresh();
    }
    final enabled = state.enabled;
    if (enabled.isEmpty) return null;
    if (_live) {
      state = state.copyWith(
        syncing: true,
        clearMessage: interactive,
        failed: false,
      );
    }
    final report = await coordinator.sync(enabled: enabled, trigger: trigger);
    if (!_live) return report;
    _failures = report.hasFailure ? _failures + 1 : 0;
    _nextAllowed = report.hasFailure
        ? DateTime.now().add(
            Duration(minutes: math.min(60, 1 << _failures.clamp(0, 6))),
          )
        : null;
    DeviceStatus? status;
    try {
      status = await ref.read(deviceImportRepositoryProvider).status();
    } catch (_) {}
    final granted = <WearableMetric>{};
    final source = _source;
    if (source != null) {
      for (final m in enabled) {
        if (await source.hasAccess(m)) granted.add(m);
      }
    }
    if (!_live) return report;
    state = state.copyWith(
      syncing: false,
      report: report,
      status: status,
      granted: granted,
      message: interactive || report.hasFailure ? describeReport(report) : null,
      failed: report.hasFailure,
      lastErrorCode: report.firstError,
      clearError: !report.hasFailure,
      lastSuccessAt: report.hasFailure ? null : report.at,
    );
    if (report.blockedBy == 'CONSENT_REQUIRED') {
      ref.invalidate(devicePreferencesProvider);
    }
    _invalidateData();
    return report;
  }

  void _invalidateData() {
    ref.invalidate(stepsSummaryProvider);
    ref.invalidate(deviceStatusProvider);
    ref.invalidate(deviceTodayProvider);
    ref.invalidate(heartRateSummaryProvider);
    ref.invalidate(heartRateDayProvider);
    ref.invalidate(todayProvider);
    ref.invalidate(clinicalSummaryProvider);
    ref.invalidate(activityPageProvider);
    ref.invalidate(activityDayProvider);
  }
}

final syncCoordinatorProvider = Provider<SyncCoordinator?>((ref) {
  final source = ref.watch(healthDataSourceProvider);
  final store = ref.watch(syncStoreProvider);
  final auth = ref.watch(authControllerProvider);
  if (source == null || store == null || auth is! AuthAuthenticated) {
    return null;
  }
  final id = auth.user.id;
  return SyncCoordinator(
    source: source,
    repo: ref.watch(deviceImportRepositoryProvider),
    store: store,
    isCurrentAccount: () {
      if (!ref.mounted) return false;
      final current = ref.read(authControllerProvider);
      return current is AuthAuthenticated && current.user.id == id;
    },
  );
});

final deviceConnectionProvider =
    NotifierProvider<DeviceConnectionController, DeviceConnectionView>(
      DeviceConnectionController.new,
    );

class DeviceAutoSync with WidgetsBindingObserver {
  DeviceAutoSync(this._ref) {
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _tick(SyncTrigger.periodic),
    );
  }
  final Ref _ref;
  Timer? _timer;
  DateTime? _last;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tick(SyncTrigger.resume);
  }

  void _tick(SyncTrigger trigger) {
    if (!_ref.mounted) return;
    final now = DateTime.now();
    if (trigger == SyncTrigger.resume &&
        _last != null &&
        now.difference(_last!) < const Duration(minutes: 5)) {
      return;
    }
    _last = now;
    unawaited(
      _ref.read(deviceConnectionProvider.notifier).syncNow(trigger: trigger),
    );
  }

  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}

final deviceAutoSyncProvider = Provider<DeviceAutoSync?>((ref) {
  if (ref.watch(authControllerProvider) is! AuthAuthenticated) return null;
  if (ref.watch(healthDataSourceProvider) == null) return null;
  final auto = DeviceAutoSync(ref);
  ref.onDispose(auto.dispose);
  return auto;
});
