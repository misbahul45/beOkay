import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/selection_card.dart';
import '../data/preferences_models.dart';

Future<String?> showTimezonePicker(
  BuildContext context, {
  required String current,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
    ),
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          0,
          AppSpacing.page,
          AppSpacing.lg,
        ),
        children: [
          Semantics(
            header: true,
            child: Text('Zona Waktu', style: AppTypography.heading),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final zone in supportedTimezones) ...[
            SelectionCard(
              title: zone.label,
              description: zone.id,
              selected: zone.id == current,
              onTap: () => Navigator.of(context).pop(zone.id),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    ),
  );
}

String timezoneLabel(String id) {
  for (final zone in supportedTimezones) {
    if (zone.id == id) return zone.label;
  }
  return id;
}
