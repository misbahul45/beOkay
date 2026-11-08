import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/pill_button.dart';
import '../data/nutrition_models.dart';

class NutritionError extends StatelessWidget {
  const NutritionError({super.key, required this.error, required this.retry});
  final Object error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) =>
      error is ApiException &&
          (error as ApiException).code == 'CONSENT_REQUIRED'
      ? InfoCard(
          title: 'Persetujuan diperlukan',
          text: 'Tinjau persetujuan untuk mengakses catatan makanan.',
          action: PillButton(
            label: 'Kelola persetujuan',
            onPressed: () => context.push(Routes.consentManagement),
          ),
        )
      : ErrorState(error: error, onRetry: retry);
}

class NutritionCard extends StatelessWidget {
  const NutritionCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.cardRadius,
    ),
    child: child,
  );
}

class NutritionTotals extends StatelessWidget {
  const NutritionTotals({super.key, required this.totals});
  final Map<String, NutrientTotal> totals;
  @override
  Widget build(BuildContext context) => NutritionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Informasi gizi', style: AppTypography.title),
        const SizedBox(height: 8),
        for (final key in nutrientLabels.keys)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '${nutrientLabels[key]}: ${totals[key]?.label(key == 'calories' ? 'kkal' : 'g') ?? 'Belum tersedia'}',
              style: AppTypography.body,
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Perhitungan dari nilai referensi dan gram yang dicatat. Total sebagian hanya mencakup item yang memiliki data.',
          style: AppTypography.secondary,
        ),
      ],
    ),
  );
}
