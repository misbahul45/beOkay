import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/consent/application/consent_controller.dart';
import '../../features/consent/data/consent_models.dart';
import '../config/app_config.dart';
import '../providers.dart';

class UsageEvent {
  UsageEvent(this.type, {this.domain, this.meta = const {}})
    : occurredAt = DateTime.now().toUtc();
  final String type;
  final String? domain;
  final Map<String, Object> meta;
  final DateTime occurredAt;

  Map<String, dynamic> toJson() => {
    'type': type,
    'domain': ?domain,
    'meta': meta,
    'occurredAt': occurredAt.toIso8601String(),
  };
}

class UsageTracker {
  UsageTracker(this._ref);
  final Ref _ref;
  final List<UsageEvent> _buffer = [];
  Timer? _timer;
  bool _sending = false;

  static const flushAt = 10;
  static const maxBuffer = 50;

  bool get _allowed {
    try {
      if (_ref.read(authControllerProvider) is! AuthAuthenticated) return false;
      final overview = _ref.read(consentControllerProvider).value;
      if (overview == null) return false;
      return overview.purposes.any(
        (p) =>
            p.purpose == 'product_analytics' &&
            p.status == ConsentStatus.granted,
      );
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  List<UsageEvent> get pending => List.unmodifiable(_buffer);

  void track(
    String type, {
    String? domain,
    Map<String, Object> meta = const {},
  }) {
    if (!_allowed) return;
    if (_buffer.length >= maxBuffer) _buffer.removeAt(0);
    _buffer.add(UsageEvent(type, domain: domain, meta: meta));
    if (_buffer.length >= flushAt) {
      unawaited(flush());
    } else {
      _timer ??= Timer(const Duration(seconds: 20), () => unawaited(flush()));
    }
  }

  void screen(String name) => track('screen_opened', meta: {'screen': name});

  void formSaved(String domain, Duration elapsed, {String via = 'form'}) =>
      track(
        'form_saved',
        domain: domain,
        meta: {
          'via': via,
          'durationMs': elapsed.inMilliseconds.clamp(0, 3600000),
        },
      );

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_sending || _buffer.isEmpty) return;
    if (!_allowed) {
      _buffer.clear();
      return;
    }
    _sending = true;
    final batch = List<UsageEvent>.from(_buffer);
    _buffer.clear();
    try {
      await _ref
          .read(apiClientProvider)
          .post(
            '/api/me/usage-events',
            body: {
              'appVersion': AppConfig.appVersion,
              if (!kIsWeb && Platform.isAndroid) 'platform': 'android',
              if (!kIsWeb && Platform.isIOS) 'platform': 'ios',
              'events': [for (final e in batch) e.toJson()],
            },
          );
    } catch (_) {
    } finally {
      _sending = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _buffer.clear();
  }
}

final usageTrackerProvider = Provider<UsageTracker>((ref) {
  ref.watch(authControllerProvider);
  ref.listen(consentControllerProvider, (_, _) {});
  final tracker = UsageTracker(ref);
  ref.onDispose(tracker.dispose);
  return tracker;
});
