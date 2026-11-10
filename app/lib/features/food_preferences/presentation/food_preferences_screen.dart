import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/food_preferences_controller.dart';
import '../data/food_preferences_repository.dart';

/// Alergi dan pembatasan adalah kendala keras; "tidak suka" hanya peringatan lunak.
/// Pengecekan di aplikasi berbasis nama makanan: bukan jaminan keamanan.
class FoodPreferencesScreen extends ConsumerWidget {
  const FoodPreferencesScreen({super.key});

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    FoodPreference p,
  ) async {
    try {
      await ref.read(foodPreferencesRepositoryProvider).archive(p);
      ref.invalidate(foodPreferencesProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFor(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(foodPreferencesProvider);
    return PageScaffold(
      title: 'Alergi dan preferensi makanan',
      onBack: () =>
          context.canPop() ? context.pop() : context.go(Routes.profile),
      bottom: PillButton(
        label: 'Tambah',
        icon: Icons.add_rounded,
        onPressed: () => showAddPreferenceSheet(context, ref),
      ),
      onRefresh: () async => ref.invalidate(foodPreferencesProvider),
      children: [
        Text(
          'Dicek dari nama makanan saja. Tetap baca label bila kamu alergi.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.md),
        AsyncBody<List<FoodPreference>>(
          value: prefs,
          onRetry: () => ref.invalidate(foodPreferencesProvider),
          skeletonRows: 3,
          data: (items) {
            if (items.isEmpty) {
              return EmptyState(
                icon: Icons.restaurant_menu_outlined,
                title: 'Belum ada yang dicatat',
                message:
                    'Tambahkan alergi, pembatasan, atau makanan yang tidak kamu suka agar pencarian makanan memberi peringatan.',
                actionLabel: 'Tambah',
                onAction: () => showAddPreferenceSheet(context, ref),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final kind in preferenceKindLabels.keys)
                  if (items.any((p) => p.kind == kind)) ...[
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 4,
                        bottom: AppSpacing.xs,
                      ),
                      child: Semantics(
                        header: true,
                        child: Text(
                          preferenceKindLabels[kind]!.toUpperCase(),
                          style: AppTypography.overline,
                        ),
                      ),
                    ),
                    Material(
                      color: AppColors.surface,
                      borderRadius: AppRadius.cardRadius,
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final p in items.where((p) => p.kind == kind))
                            ListTile(
                              title: Text(
                                p.label,
                                style: AppTypography.bodyStrong,
                              ),
                              subtitle: Text(
                                p.strict
                                    ? 'Kendala keras: dikecualikan di pencarian'
                                    : 'Peringatan lunak',
                                style: AppTypography.caption,
                              ),
                              trailing: IconButton(
                                tooltip: 'Hapus ${p.label}',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => _archive(context, ref, p),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
              ],
            );
          },
        ),
      ],
    );
  }
}

Future<void> showAddPreferenceSheet(BuildContext context, WidgetRef ref) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddSheet(ref: ref),
    );

class _AddSheet extends StatefulWidget {
  const _AddSheet({required this.ref});
  final WidgetRef ref;
  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  final term = TextEditingController();
  String kind = 'allergy';
  bool busy = false;
  Object? error;

  @override
  void dispose() {
    term.dispose();
    super.dispose();
  }

  Future<void> save(String value) async {
    final t = value.trim();
    if (t.length < 2) {
      setState(() => error = 'Isi minimal dua karakter.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.ref
          .read(foodPreferencesRepositoryProvider)
          .add(kind: kind, term: t);
      widget.ref.invalidate(foodPreferencesProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = switch (kind) {
      'allergy' => commonAllergens,
      'restriction' => restrictionPresets,
      _ => const <(String, String)>[],
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        24,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text('Tambah', style: AppTypography.headline),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              children: [
                for (final e in preferenceKindLabels.entries)
                  PillChip(
                    label: e.value,
                    selected: kind == e.key,
                    onTap: busy ? null : () => setState(() => kind = e.key),
                  ),
              ],
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('Pilihan cepat', style: AppTypography.caption),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in suggestions)
                    PillChip(
                      label: s.$2,
                      selected: false,
                      onTap: busy ? null : () => save(s.$1),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              label: 'Atau tulis sendiri',
              hint: kind == 'allergy' ? 'mis. kerang' : 'mis. pare',
              controller: term,
              maxLength: 40,
              onSubmitted: save,
            ),
            if (error != null)
              ErrorBanner(
                error is String ? error.toString() : messageFor(error!),
              ),
            const SizedBox(height: AppSpacing.sm),
            PillButton(
              label: 'Simpan',
              loading: busy,
              onPressed: () => save(term.text),
            ),
          ],
        ),
      ),
    );
  }
}
