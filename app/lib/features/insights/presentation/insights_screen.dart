import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/tab_root_header.dart';
import '../application/insights_controller.dart';
import 'daily_tab.dart';
import 'insight_widgets.dart';
import 'summary_tab.dart';
import 'trends_screen.dart';

const insightsSectionLabels = ['Ringkasan', 'Tren', 'Harian'];

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  Future<void> _refresh(WidgetRef ref, InsightsSection section) async {
    switch (section) {
      case InsightsSection.summary:
        final days = ref.read(trendRangeProvider);
        ref.invalidate(statisticsProvider(days));
        await ref.read(statisticsProvider(days).future).catchError((_) => null);
      case InsightsSection.trends:
        ref.invalidate(trendsProvider);
        await ref.read(trendsProvider.future).catchError((_) => null);
      case InsightsSection.daily:
        ref.invalidate(dailyInsightsProvider);
        ref.invalidate(contextualInsightsProvider);
        ref.invalidate(dailyMedicationProvider);
        await ref.read(dailyInsightsProvider.future).catchError((_) => null);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(insightsSectionProvider);
    final reduce = MediaQuery.of(context).disableAnimations;
    return PageScaffold(
      showBack: false,
      onRefresh: () => _refresh(ref, section),
      children: [
        const TabRootHeader(
          title: 'Wawasan',
          subtitle: 'Pola dari catatanmu sendiri',
        ),
        const SizedBox(height: AppSpacing.sm),
        SectionTabs(
          labels: insightsSectionLabels,
          value: section.index,
          onChanged: (i) => ref
              .read(insightsSectionProvider.notifier)
              .set(InsightsSection.values[i]),
        ),
        const SizedBox(height: AppSpacing.md),
        AnimatedSwitcher(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, ?current],
          ),
          child: KeyedSubtree(
            key: ValueKey(section),
            child: switch (section) {
              InsightsSection.summary => const SummaryTab(),
              InsightsSection.trends => const TrendsBody(),
              InsightsSection.daily => const DailyTab(),
            },
          ),
        ),
      ],
    );
  }
}
