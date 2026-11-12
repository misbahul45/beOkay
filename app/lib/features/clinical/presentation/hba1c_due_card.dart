import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/clinical_controller.dart';

class Hba1cDueCard extends ConsumerWidget {
  const Hba1cDueCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(clinicalSummaryProvider).value;
    if (s == null || !s.hba1c.due) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InfoCard(
        icon: Icons.science_outlined,
        title: 'Sudah ${s.hba1c.daysSince} hari sejak HbA1c terakhir',
        text:
            'Bila kamu sudah periksa, catat hasilnya. Jadwal periksa tetap mengikuti saran tenaga kesehatanmu.',
        action: PillButton(
          label: 'Catat hasil lab',
          kind: PillButtonKind.secondary,
          expand: false,
          onPressed: () => context.push('${Routes.addLab}?test=hba1c'),
        ),
      ),
    );
  }
}
