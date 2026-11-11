import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../consent/application/consent_controller.dart';
import '../../medication/application/medication_controller.dart';
import '../../medication/data/medication_repository.dart';
import '../../preferences/application/preferences_controller.dart';
import '../data/contextual_insights.dart';
import '../data/daily_insights.dart';
import '../data/statistics.dart';
import '../data/insights_repository.dart';
import '../data/trends.dart';

final insightsRepositoryProvider = Provider<InsightsRepository>(
  (ref) => InsightsRepository(ref.watch(apiClientProvider)),
);

final insightsDateProvider =
    NotifierProvider.autoDispose<InsightsDateNotifier, String?>(
      InsightsDateNotifier.new,
    );

class InsightsDateNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? date) => state = date;
}

final dailyInsightsProvider = FutureProvider.autoDispose<DailyInsights?>((
  ref,
) async {
  if (ref.watch(authControllerProvider) is! AuthAuthenticated) return null;
  final date = ref.watch(insightsDateProvider);
  await Future.wait([
    ref.watch(consentControllerProvider.future),
    ref.watch(preferencesControllerProvider.future),
  ]);
  return ref.watch(insightsRepositoryProvider).daily(date: date);
});

final trendRangeProvider = NotifierProvider<TrendRangeNotifier, int>(
  TrendRangeNotifier.new,
);

class TrendRangeNotifier extends Notifier<int> {
  @override
  int build() => 14;
  void set(int days) => state = days;
}

final trendsProvider = FutureProvider.autoDispose<Trends?>((ref) async {
  if (ref.watch(authControllerProvider) is! AuthAuthenticated) return null;
  final days = ref.watch(trendRangeProvider);
  await Future.wait([
    ref.watch(consentControllerProvider.future),
    ref.watch(preferencesControllerProvider.future),
  ]);
  return ref.watch(insightsRepositoryProvider).trends(days: days);
});

final statisticsProvider = FutureProvider.autoDispose.family<Statistics?, int>((
  ref,
  days,
) async {
  if (ref.watch(authControllerProvider) is! AuthAuthenticated) return null;
  await Future.wait([
    ref.watch(consentControllerProvider.future),
    ref.watch(preferencesControllerProvider.future),
  ]);
  return ref.watch(insightsRepositoryProvider).statistics(days: days);
});

final contextualInsightsProvider =
    FutureProvider.autoDispose<ContextualInsights?>((ref) async {
      if (ref.watch(authControllerProvider) is! AuthAuthenticated) return null;
      await Future.wait([
        ref.watch(consentControllerProvider.future),
        ref.watch(preferencesControllerProvider.future),
      ]);
      try {
        return await ref.watch(insightsRepositoryProvider).contextual();
      } catch (_) {
        return null;
      }
    });

enum InsightsSection { summary, trends, daily }

final insightsSectionProvider =
    NotifierProvider<InsightsSectionNotifier, InsightsSection>(
      InsightsSectionNotifier.new,
    );

class InsightsSectionNotifier extends Notifier<InsightsSection> {
  @override
  InsightsSection build() => InsightsSection.summary;
  void set(InsightsSection s) => state = s;
}

final dailyMedicationProvider = FutureProvider.autoDispose<MedicationToday?>((
  ref,
) async {
  if (ref.watch(authControllerProvider) is! AuthAuthenticated) return null;
  final date = ref.watch(insightsDateProvider);
  await Future.wait([
    ref.watch(consentControllerProvider.future),
    ref.watch(preferencesControllerProvider.future),
  ]);
  return ref.watch(medicationRepositoryProvider).today(date: date);
});
