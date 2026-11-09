import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../consent/application/consent_controller.dart';
import '../../preferences/application/preferences_controller.dart';
import '../data/daily_insights.dart';
import '../data/insights_repository.dart';
import '../data/trends.dart';
import '../data/weekly_insights.dart';

final insightsRepositoryProvider = Provider<InsightsRepository>((ref) => InsightsRepository(ref.watch(apiClientProvider)));

/// Selected day for the Insights tab; null means "today in the user's timezone" (server default).
final insightsDateProvider = NotifierProvider.autoDispose<InsightsDateNotifier, String?>(InsightsDateNotifier.new);

class InsightsDateNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? date) => state = date;
}

final dailyInsightsProvider = FutureProvider.autoDispose<DailyInsights?>((ref) async {
  if (ref.watch(authControllerProvider) is! AuthAuthenticated) return null;
  final date = ref.watch(insightsDateProvider);
  await Future.wait([ref.watch(consentControllerProvider.future), ref.watch(preferencesControllerProvider.future)]);
  return ref.watch(insightsRepositoryProvider).daily(date: date);
});

/// Ringkasan mingguan lintas domain untuk hari yang sedang dilihat.
final weeklyInsightsProvider = FutureProvider.autoDispose<WeeklyInsights?>((ref) async {
  if (ref.watch(authControllerProvider) is! AuthAuthenticated) return null;
  final date = ref.watch(insightsDateProvider);
  await Future.wait([ref.watch(consentControllerProvider.future), ref.watch(preferencesControllerProvider.future)]);
  return ref.watch(insightsRepositoryProvider).weekly(date: date);
});

/// Rentang tren (hari): 7, 14, 30, atau 90. Satu pilihan untuk semua grafik.
final trendRangeProvider = NotifierProvider<TrendRangeNotifier, int>(TrendRangeNotifier.new);

class TrendRangeNotifier extends Notifier<int> {
  @override
  int build() => 14;
  void set(int days) => state = days;
}

final trendsProvider = FutureProvider.autoDispose<Trends?>((ref) async {
  if (ref.watch(authControllerProvider) is! AuthAuthenticated) return null;
  final days = ref.watch(trendRangeProvider);
  await Future.wait([ref.watch(consentControllerProvider.future), ref.watch(preferencesControllerProvider.future)]);
  return ref.watch(insightsRepositoryProvider).trends(days: days);
});
