import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/usage_tracker.dart';
import '../../core/providers.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/info_card.dart';
import '../../core/widgets/page_scaffold.dart';

class EducationItem {
  EducationItem.fromJson(Map<String, dynamic> j)
    : key = j['key'] as String,
      title = j['title'] as String,
      summary = (j['summary'] as String?) ?? '',
      readMinutes = (j['readMinutes'] as num).toInt(),
      reviewed = j['reviewStatus'] == 'REVIEWED';
  final String key, title, summary;
  final int readMinutes;
  final bool reviewed;
}

class EducationSection {
  EducationSection.fromJson(Map<String, dynamic> j)
    : heading = j['heading'] as String,
      paragraphs = (j['paragraphs'] as List).cast<String>(),
      bullets = (j['bullets'] as List).cast<String>();
  final String heading;
  final List<String> paragraphs, bullets;
}

class EducationModule {
  EducationModule.fromJson(Map<String, dynamic> j)
    : item = EducationItem.fromJson(j),
      version = (j['version'] as num).toInt(),
      authoredOn = j['authoredOn'] as String,
      reviewedBy = j['reviewedBy'] as String?,
      notice = j['notice'] as String,
      sections = [
        for (final s in j['sections'] as List)
          EducationSection.fromJson(s as Map<String, dynamic>),
      ];
  final EducationItem item;
  final int version;
  final String authoredOn, notice;
  final String? reviewedBy;
  final List<EducationSection> sections;
}

class EducationRepository {
  EducationRepository(this.api);
  final ApiClient api;
  Future<List<EducationItem>> list() async => [
    for (final m
        in (await api.get('/api/education/modules')).object['items'] as List)
      EducationItem.fromJson(m as Map<String, dynamic>),
  ];
  Future<EducationModule> get(String key) async => EducationModule.fromJson(
    (await api.get('/api/education/modules/$key')).object,
  );
}

final educationRepositoryProvider = Provider<EducationRepository>(
  (ref) => EducationRepository(ref.watch(apiClientProvider)),
);
final educationListProvider = FutureProvider.autoDispose<List<EducationItem>>(
  (ref) => ref.watch(educationRepositoryProvider).list(),
);
final educationModuleProvider = FutureProvider.autoDispose
    .family<EducationModule, String>(
      (ref, key) => ref.watch(educationRepositoryProvider).get(key),
    );

String educationRoute(String key) => '/learn/$key';

class DraftBadge extends StatelessWidget {
  const DraftBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.warningBackground,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      'DRAF · menunggu tinjauan klinisi',
      style: AppTypography.caption.copyWith(
        color: AppColors.warningForeground,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class EducationListScreen extends ConsumerWidget {
  const EducationListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(educationListProvider);
    return PageScaffold(
      title: 'Belajar diabetes',
      children: [
        const InfoCard(
          tone: InfoTone.neutral,
          text:
              'Bacaan singkat 3–5 menit. Untuk keputusan obat dan pengobatan, tetap bicarakan dengan dokter atau tenaga kesehatanmu.',
        ),
        const SizedBox(height: AppSpacing.sm),
        list.when(
          loading: () => const SkeletonList(rows: 5),
          error: (e, _) => ErrorState(
            error: e,
            onRetry: () => ref.invalidate(educationListProvider),
          ),
          data: (items) => items.isEmpty
              ? Text(
                  'Modul sedang ditinjau tenaga kesehatan dan belum tersedia.',
                  style: AppTypography.secondary,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final m in items)
                      Card(
                        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: ListTile(
                          leading: const Icon(Icons.menu_book_outlined),
                          title: Text(m.title),
                          subtitle: Text(
                            '${m.readMinutes} menit${m.reviewed ? '' : ' · draf'}\n${m.summary}',
                          ),
                          isThreeLine: true,
                          onTap: () => context.push(educationRoute(m.key)),
                        ),
                      ),
                    if (items.any((m) => !m.reviewed)) const DraftBadge(),
                  ],
                ),
        ),
      ],
    );
  }
}

class EducationModuleScreen extends ConsumerStatefulWidget {
  const EducationModuleScreen({super.key, required this.moduleKey});
  final String moduleKey;
  @override
  ConsumerState<EducationModuleScreen> createState() =>
      _EducationModuleScreenState();
}

class _EducationModuleScreenState extends ConsumerState<EducationModuleScreen> {
  @override
  void initState() {
    super.initState();
    ref
        .read(usageTrackerProvider)
        .track(
          'education_opened',
          domain: 'education',
          meta: {'kind': widget.moduleKey.replaceAll('-', '_')},
        );
  }

  @override
  Widget build(BuildContext context) {
    final module = ref.watch(educationModuleProvider(widget.moduleKey));
    return PageScaffold(
      title: module.value?.item.title ?? 'Belajar diabetes',
      children: [
        module.when(
          loading: () => const SkeletonList(rows: 4),
          error: (e, _) => ErrorState(
            error: e,
            onRetry: () =>
                ref.invalidate(educationModuleProvider(widget.moduleKey)),
          ),
          data: (m) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!m.item.reviewed) ...[
                const DraftBadge(),
                const SizedBox(height: AppSpacing.sm),
              ],
              for (final s in m.sections) ...[
                if (s.heading.isNotEmpty)
                  Semantics(
                    header: true,
                    child: Text(s.heading, style: AppTypography.title),
                  ),
                const SizedBox(height: 4),
                for (final p in s.paragraphs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(p, style: AppTypography.body),
                  ),
                for (final b in s.bullets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('•  ', style: AppTypography.body),
                        Expanded(child: Text(b, style: AppTypography.body)),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Text(m.notice, style: AppTypography.secondary),
              const SizedBox(height: 4),
              Text(
                'Versi ${m.version} · ditulis ${m.authoredOn}${m.reviewedBy == null ? ' · belum ditinjau klinisi' : ' · ditinjau ${m.reviewedBy}'}',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class EducationLinks extends StatelessWidget {
  const EducationLinks({super.key, required this.items});
  final List<EducationItem> items;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final m in items)
        Card(
          margin: const EdgeInsets.only(top: AppSpacing.xs),
          child: ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: Text('Baca: ${m.title}'),
            subtitle: Text(
              'Modul edukasi · ${m.readMinutes} menit${m.reviewed ? '' : ' · draf'}',
            ),
            onTap: () => context.push(educationRoute(m.key)),
          ),
        ),
    ],
  );
}
