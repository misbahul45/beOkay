import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../auth/application/auth_controller.dart';

final featuresProvider = FutureProvider<Map<String, bool>>((ref) async {
  if (ref.watch(authControllerProvider) is! AuthAuthenticated) return const {};
  try {
    final r = await ref.read(apiClientProvider).get('/api/me/features');
    return ((r.object['features'] as Map?) ?? const {}).map(
      (k, v) => MapEntry(k as String, v == true),
    );
  } catch (_) {
    return const {};
  }
});

bool featureOn(Map<String, bool>? features, String key) =>
    features == null || (features[key] ?? true);
