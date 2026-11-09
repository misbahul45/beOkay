import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/info_card.dart';
import '../../../../core/widgets/page_scaffold.dart';
import '../../../../core/widgets/pill_button.dart';
import '../../data/nutrition_models.dart';
import 'scan_widgets.dart';

/// Pilihan pengguna dari layar hasil: makanan dari katalog, atau kata kunci untuk dicari manual.
class ScanOutcome {
  const ScanOutcome.food(FoodReference this.food) : query = null;
  const ScanOutcome.search(String this.query) : food = null;
  final FoodReference? food;
  final String? query;
}

/// Hasil pengenalan foto: hanya nama kandidat. Berat dan gizi tidak pernah ditebak dari gambar.
class PhotoResultScreen extends StatelessWidget {
  const PhotoResultScreen({super.key, required this.scan});
  final PhotoScan scan;

  @override
  Widget build(BuildContext context) => PageScaffold(
    title: 'Yang terlihat di foto',
    onBack: () => Navigator.pop(context),
    children: [
      const Align(alignment: Alignment.centerLeft, child: ProvenanceChip('Tebakan dari foto · Bukan data gizi')),
      const SizedBox(height: AppSpacing.sm),
      for (final item in scan.items) ...[_ItemCard(item: item), const SizedBox(height: AppSpacing.sm)],
      const InfoCard(tone: InfoTone.info, text: 'Foto hanya membantu mengenali nama. Berat dan gizi tidak ditebak dari gambar — kamu yang menentukan porsinya.'),
      const SizedBox(height: AppSpacing.md),
      PillButton(label: 'Bukan ini? Cari manual', kind: PillButtonKind.secondary, onPressed: () => Navigator.pop(context)),
    ],
  );
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});
  final PhotoMatch item;

  @override
  Widget build(BuildContext context) {
    final (tint, ink) = switch (item.confidence) {
      'high' => (AppColors.mealTint, AppColors.mealInk),
      'medium' => (AppColors.glucoseTint, AppColors.glucoseInk),
      _ => (AppColors.goalTint, AppColors.goalInk),
    };
    final match = item.matches.isEmpty ? null : item.matches.first;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.cardRadius, border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(item.name, style: AppTypography.bodyStrong)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Text(item.confidenceLabel, style: AppTypography.caption.copyWith(color: ink, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(match == null ? 'Belum ada di katalog kamu.' : 'Ada di katalog: ${match.name} · per 100 g', style: AppTypography.secondary),
          const SizedBox(height: AppSpacing.sm),
          if (match != null)
            PillButton(label: 'Pakai ini, lalu isi berat', onPressed: () => Navigator.pop(context, ScanOutcome.food(match)))
          else
            PillButton(label: 'Cari “${item.name}”', kind: PillButtonKind.secondary, onPressed: () => Navigator.pop(context, ScanOutcome.search(item.name))),
        ],
      ),
    );
  }
}
