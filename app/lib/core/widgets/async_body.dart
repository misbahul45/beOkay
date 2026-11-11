import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/error_messages.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'pill_button.dart';

class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    this.height = 56,
    this.width,
    this.radius = AppRadius.input,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width ?? double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 3});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Memuat',
      liveRegion: true,
      child: Column(
        children: [
          for (var index = 0; index < rows; index++) ...[
            const SkeletonBlock(height: 72, radius: AppRadius.card),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 36, color: AppColors.decorative),
          const SizedBox(height: AppSpacing.sm),
          Text('Belum bisa memuat', style: AppTypography.title),
          const SizedBox(height: 4),
          Text(
            messageFor(error),
            textAlign: TextAlign.center,
            style: AppTypography.secondary,
          ),
          const SizedBox(height: AppSpacing.md),
          PillButton(
            label: 'Coba lagi',
            kind: PillButtonKind.secondary,
            onPressed: onRetry,
            expand: false,
          ),
        ],
      ),
    );
  }
}

class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.value,
    required this.data,
    required this.onRetry,
    this.skeletonRows = 3,
  });

  final AsyncValue<T> value;
  final Widget Function(T value) data;
  final VoidCallback onRetry;
  final int skeletonRows;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () => SkeletonList(rows: skeletonRows),
      error: (error, _) => ErrorState(error: error, onRetry: onRetry),
    );
  }
}
