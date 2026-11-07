import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../consent/application/consent_controller.dart';
import '../../preferences/application/preferences_controller.dart';
import '../../profile/application/profile_controller.dart';
import '../data/today_overview.dart';
import '../data/today_repository.dart';

final todayRepositoryProvider = Provider<TodayRepository>(
  (ref) => TodayRepository(ref.watch(apiClientProvider)),
);

final todayProvider = FutureProvider.autoDispose<TodayOverview?>((ref) async {
  if (ref.watch(authControllerProvider) is! AuthAuthenticated) return null;
  final repository = ref.watch(todayRepositoryProvider);
  final dependencies = [
    ref.watch(consentControllerProvider.future),
    ref.watch(preferencesControllerProvider.future),
    ref.watch(profileControllerProvider.future),
  ];
  final timer = Timer(const Duration(minutes: 1), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  await Future.wait(dependencies);
  return repository.get();
});
