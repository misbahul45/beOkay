import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/domain_style.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/timeline_tile.dart';
import '../../quick_record/presentation/quick_record_sheet.dart';
import '../application/timeline_controller.dart';
import '../data/timeline_models.dart';

/// "Catatan" tab: one chronological journal across supported health domains.
class LogScreen extends ConsumerWidget {
  const LogScreen({super.key});

  static const _domains = [
    ('all', 'Semua'),
    ('meal', 'Makanan'),
    ('glucose', 'Glukosa'),
    ('activity', 'Aktivitas'),
    ('medication', 'Obat'),
    ('goal', 'Tujuan'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(logFilterProvider);
    final feed = ref.watch(logFeedProvider);
    final isFiltered = filter.domain != 'all' || filter.date != null;
    void set(LogFilter next) => ref.read(logFilterProvider.notifier).set(next);

    return PageScaffold(
      showBack: false,
      onRefresh: () async {
        ref.invalidate(logFeedProvider);
        await ref
            .read(logFeedProvider.future)
            .catchError((_) => const LogFeed());
      },
      children: [
        Semantics(
          header: true,
          child: Text('Catatan', style: AppTypography.headline),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Diurutkan menurut waktu kejadian, bukan waktu kamu menginputnya.',
          style: AppTypography.secondary,
        ),
        const SizedBox(height: AppSpacing.md),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (key, label) in _domains) ...[
                PillChip(
                  label: label,
                  selected: filter.domain == key,
                  onTap: () => set(filter.copyWith(domain: key)),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            PillChip(
              label: filter.date == null
                  ? 'Pilih tanggal'
                  : _dateLabel(filter.date!),
              selected: filter.date != null,
              onTap: () async {
                final now = DateTime.now();
                final current = filter.date == null
                    ? null
                    : DateTime.tryParse(filter.date!);
                final chosen = await showDatePicker(
                  context: context,
                  initialDate: current ?? now,
                  firstDate: DateTime(2000),
                  lastDate: now.add(const Duration(days: 1)),
                );
                if (chosen != null) {
                  set(
                    filter.copyWith(
                      date: DateFormat('yyyy-MM-dd').format(chosen),
                    ),
                  );
                }
              },
            ),
            if (filter.date != null)
              PillChip(
                label: 'Semua tanggal',
                selected: false,
                onTap: () => set(filter.copyWith(date: null)),
              ),
            PillChip(
              label: 'Diarsipkan',
              selected: filter.archived,
              onTap: () => set(filter.copyWith(archived: !filter.archived)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        feed.when(
          skipLoadingOnReload: false,
          skipLoadingOnRefresh: true,
          loading: () => const SkeletonList(rows: 4),
          error: (error, _) {
            if (error is ApiException && error.code == 'CONSENT_REQUIRED') {
              return InfoCard(
                title: 'Persetujuan diperlukan',
                text: 'Tinjau persetujuan untuk membuka catatan kesehatanmu.',
                action: PillButton(
                  label: 'Kelola persetujuan',
                  expand: false,
                  onPressed: () => context.push(Routes.consentManagement),
                ),
              );
            }
            return ErrorState(
              error: error,
              onRetry: () => ref.invalidate(logFeedProvider),
            );
          },
          data: (data) {
            if (data.items.isEmpty) {
              return EmptyState(
                icon: isFiltered || filter.archived
                    ? Icons.filter_alt_off_outlined
                    : Icons.edit_note_rounded,
                title: filter.archived
                    ? 'Belum ada catatan diarsipkan'
                    : isFiltered
                    ? 'Tidak ada catatan pada filter ini'
                    : 'Belum ada catatan',
                message: filter.archived
                    ? 'Catatan yang kamu arsipkan muncul di sini dan bisa dipulihkan.'
                    : isFiltered
                    ? 'Coba ganti jenis catatan atau tanggal.'
                    : 'Mulai dengan satu catatan. Kamu yang menentukan apa yang dicatat.',
                actionLabel: isFiltered
                    ? 'Hapus filter'
                    : (filter.archived ? null : 'Mulai mencatat'),
                onAction: isFiltered
                    ? () => set(filter.copyWith(domain: 'all', date: null))
                    : () => showQuickRecord(context),
              );
            }
            return _Feed(
              data: data,
              onMore: () => ref.read(logFeedProvider.notifier).loadMore(),
            );
          },
        ),
      ],
    );
  }

  static String _dateLabel(String iso) {
    final parsed = DateTime.tryParse(iso);
    return parsed == null ? iso : DateFormat('d MMM y', 'id_ID').format(parsed);
  }
}

class _Feed extends StatelessWidget {
  const _Feed({required this.data, required this.onMore});

  final LogFeed data;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<TimelineItem>>{};
    for (final item in data.items) {
      groups.putIfAbsent(item.localDate, () => []).add(item);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.xs,
              bottom: AppSpacing.xs,
            ),
            child: Semantics(
              header: true,
              child: Text(_heading(entry.key), style: AppTypography.overline),
            ),
          ),
          for (final item in entry.value) ...[
            TimelineTile(
              item: item,
              onTap: () => context.push(
                DomainStyle.of(item.domain).detailRoute(item.recordId),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
        if (data.moreError != null) ...[
          const SizedBox(height: AppSpacing.xs),
          ErrorBanner(messageFor(data.moreError!)),
        ],
        if (data.nextCursor != null) ...[
          const SizedBox(height: AppSpacing.xs),
          PillButton(
            label: 'Muat catatan lebih lama',
            kind: PillButtonKind.secondary,
            loading: data.loadingMore,
            onPressed: onMore,
          ),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(
              child: Text(
                'Semua catatan sudah tampil',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        if (data.timezone != null)
          Center(
            child: Text(
              'Waktu lokal: ${data.timezone}',
              style: AppTypography.caption,
            ),
          ),
      ],
    );
  }

  static String _heading(String iso) {
    final parsed = DateTime.tryParse(iso);
    return parsed == null
        ? iso
        : DateFormat('EEEE, d MMMM y', 'id_ID').format(parsed).toUpperCase();
  }
}
