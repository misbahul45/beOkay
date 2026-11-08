import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/health_card.dart';
import '../data/glucose_models.dart';

class GlucoseChart extends StatelessWidget {
  const GlucoseChart({super.key, required this.items, required this.unit});
  final List<GlucoseRecord> items;
  final String unit;
  @override
  Widget build(BuildContext context) {
    final ordered = [...items]
      ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
    if (ordered.isEmpty) return const SizedBox.shrink();
    final values = ordered.map((r) => r.displayValue.toDouble());
    final min = values.reduce((a, b) => a < b ? a : b),
        max = values.reduce((a, b) => a > b ? a : b);
    return HealthCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pengamatan pada halaman ini · $unit'),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 64,
                child: Column(
                  children: [
                    Text('$max'),
                    const SizedBox(height: 96),
                    Text('$min'),
                  ],
                ),
              ),
              Expanded(
                child: Semantics(
                  label:
                      '${ordered.length} titik pengukuran; nilai dan waktu tersedia pada daftar di bawah.',
                  image: true,
                  child: SizedBox(
                    height: 144,
                    child: CustomPaint(painter: _Points(ordered, min, max)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 24,
            children: [
              Text('${ordered.first.localDate} ${ordered.first.localTime}'),
              Text('${ordered.last.localDate} ${ordered.last.localTime}'),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Sumbu X: waktu pengukuran. Sumbu Y: nilai teramati. Titik terpisah; tidak mengisi jeda atau memperkirakan nilai di antaranya. Lingkaran kosong: perlu ditinjau.',
          ),
        ],
      ),
    );
  }
}

class _Points extends CustomPainter {
  _Points(this.items, this.minimum, this.maximum);
  final List<GlucoseRecord> items;
  final double minimum, maximum;
  @override
  void paint(Canvas canvas, Size size) {
    const margin = 8.0;
    final paint = Paint()
      ..color = AppColors.textSecondary
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(margin, margin),
      Offset(margin, size.height - margin),
      paint,
    );
    canvas.drawLine(
      Offset(margin, size.height - margin),
      Offset(size.width - margin, size.height - margin),
      paint,
    );
    final start = items.first.measuredAt.millisecondsSinceEpoch,
        span = items.last.measuredAt.millisecondsSinceEpoch - start;
    for (final record in items) {
      final x =
          margin +
          (span == 0
                  ? 0.5
                  : (record.measuredAt.millisecondsSinceEpoch - start) / span) *
              (size.width - 2 * margin);
      final y =
          margin +
          (maximum == minimum
                  ? 0.5
                  : (maximum - record.displayValue) / (maximum - minimum)) *
              (size.height - 2 * margin);
      paint
        ..color = AppColors.primary
        ..strokeWidth = 2
        ..style = record.qualityStatus == 'needs_review'
            ? PaintingStyle.stroke
            : PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), 4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _Points oldDelegate) =>
      oldDelegate.items != items ||
      oldDelegate.minimum != minimum ||
      oldDelegate.maximum != maximum;
}
