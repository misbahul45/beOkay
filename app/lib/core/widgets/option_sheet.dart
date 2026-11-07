import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'selection_card.dart';

Future<T?> showOptionSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String, String?)> options,
  required T current,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.lg),
        children: [
          Semantics(header: true, child: Text(title, style: AppTypography.heading)),
          const SizedBox(height: AppSpacing.sm),
          for (final (value, label, description) in options) ...[
            SelectionCard(title: label, description: description, selected: value == current, onTap: () => Navigator.of(context).pop(value)),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    ),
  );
}
