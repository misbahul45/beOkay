import 'package:flutter/material.dart';
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
              'Jumlah sesi tercatat tidak menggambarkan seluruh aktivitasmu.\nSumber: sesi manual, dilaporkan sendiri.\nCakupan: ${summary.eligibleCount} sesi tanpa tanda peninjauan.\nDurasi dijumlahkan per sesi; waktu yang tumpang tindih tidak dihapus. Sesi dihitung pada tanggal mulai, termasuk yang melewati tengah malam.\n${summary.computationVersion}\nDihitung: ${summary.computedAt}',
            ),
          ],
        ),
      ],
    ),
  );
}
