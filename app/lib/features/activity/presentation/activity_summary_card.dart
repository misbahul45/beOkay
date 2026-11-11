import 'package:flutter/material.dart';
import '../../../core/format/formatters.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/health_card.dart';
import '../data/activity_models.dart';

class ActivitySummaryCard extends StatelessWidget {
  const ActivitySummaryCard({
    super.key,
    required this.summary,
    required this.title,
  });
  final ActivitySummary summary;
  final String title;
  @override
  Widget build(BuildContext context) => HealthCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.title),
        const SizedBox(height: 4),
        Text(
          summary.durationMinutes == null
              ? 'Belum ada durasi tercatat'
              : '${summary.durationMinutes} menit sesi tercatat',
          style: summary.durationMinutes == null
              ? AppTypography.body
              : AppTypography.heading,
        ),
        Text(
          '${summary.count} sesi · ${summary.reviewCount} perlu ditinjau',
          style: AppTypography.secondary,
        ),
        Text(
          'Jarak: ${summary.distanceKm.label('km')} · Langkah: ${summary.steps.label('langkah')}',
          style: AppTypography.secondary,
        ),
        ExpansionTile(
          title: const Text('Metode dan cakupan'),
          children: [
            Text(
              'Dari ${summary.eligibleCount} sesi yang kamu catat; sesi yang perlu ditinjau tidak dihitung. Durasi dijumlahkan per sesi dan dihitung pada tanggal mulai. Sesi tercatat belum tentu seluruh aktivitasmu.\n${updatedAtLabel(summary.computedAt)}',
            ),
          ],
        ),
      ],
    ),
  );
}
