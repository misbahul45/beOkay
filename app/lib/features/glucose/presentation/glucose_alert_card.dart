import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/info_card.dart';
import '../data/glucose_models.dart';

class GlucoseAlertCard extends StatelessWidget {
  const GlucoseAlertCard({super.key, required this.alert});
  final GlucoseAlert alert;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Semantics(
      liveRegion: true,
      child: InfoCard(
        tone: InfoTone.error,
        icon: alert.low ? Icons.south_rounded : Icons.north_rounded,
        title: alert.title,
        text: alert.message,
      ),
    ),
  );
}
