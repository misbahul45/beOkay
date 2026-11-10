import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/page_scaffold.dart';
import '../../../../core/widgets/pill_button.dart';
import '../../data/nutrition_models.dart';

/// Pilihan pengguna dari layar hasil: makanan dari katalog, atau kata kunci untuk dicari manual.
class ScanOutcome {
  const ScanOutcome.food(FoodReference this.food) : query = null;
  const ScanOutcome.search(String this.query) : food = null;
  final FoodReference? food;
  final String? query;
}

/// Hasil pengenalan foto. Nama dikenali dari foto; gizi diambil dari Tabel Komposisi Pangan Indonesia, tidak pernah ditebak dari gambar.
class PhotoResultScreen extends StatefulWidget {
  const PhotoResultScreen({super.key, required this.scan, this.saveReference});
  final PhotoScan scan;

  /// Menyimpan padanan gizi sebagai makanan pengguna (berstatus estimasi). Null: tombol memakai pencarian manual.
  final Future<FoodReference> Function(ReferenceFood)? saveReference;

  @override
  State<PhotoResultScreen> createState() => _PhotoResultScreenState();
}

class _PhotoResultScreenState extends State<PhotoResultScreen> {
  bool saving = false;

  Future<void> use(ReferenceFood r) async {
    setState(() => saving = true);
    try {
      final food = await widget.saveReference!(r);
      if (mounted) Navigator.pop(context, ScanOutcome.food(food));
    } catch (_) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Belum bisa dipakai. Coba lagi.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = widget.scan.modelHint;
    return PageScaffold(
      title: 'Yang terlihat di foto',
      onBack: () => Navigator.pop(context),
      children: [
        for (final item in widget.scan.items) ...[
          _ItemCard(
            item: item,
            busy: saving,
            onUseReference: widget.saveReference == null ? null : use,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'Mungkin juga: ${hint.label} (${hint.percent}% yakin). Periksa dulu.',
              style: AppTypography.caption,
            ),
          ),
        PillButton(
          label: 'Bukan ini? Cari manual',
          kind: PillButtonKind.secondary,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, this.busy = false, this.onUseReference});
  final PhotoMatch item;
  final bool busy;
  final Future<void> Function(ReferenceFood)? onUseReference;

  @override
  Widget build(BuildContext context) {
    final (tint, ink) = switch (item.confidence) {
      'high' => (AppColors.mealTint, AppColors.mealInk),
      'medium' => (AppColors.glucoseTint, AppColors.glucoseInk),
      _ => (AppColors.goalTint, AppColors.goalInk),
    };
    final match = item.matches.isEmpty ? null : item.matches.first;
    final ref = item.reference.isEmpty ? null : item.reference.first;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(item.name, style: AppTypography.bodyStrong)),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  item.confidenceLabel,
                  style: AppTypography.caption.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            match != null
                ? 'Ada di daftar makananmu'
                : ref != null
                ? '${ref.summary} · ${ref.name}'
                : 'Gizinya belum ketemu.',
            style: AppTypography.secondary,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (match != null)
            PillButton(
              label: 'Pakai ini, lalu isi berat',
              onPressed: () => Navigator.pop(context, ScanOutcome.food(match)),
            )
          else if (ref != null && onUseReference != null)
            PillButton(
              label: 'Pakai ini, lalu isi berat',
              loading: busy,
              onPressed: busy ? null : () => onUseReference!(ref),
            )
          else
            PillButton(
              label: 'Cari “${item.name}”',
              kind: PillButtonKind.secondary,
              onPressed: () =>
                  Navigator.pop(context, ScanOutcome.search(item.name)),
            ),
        ],
      ),
    );
  }
}
