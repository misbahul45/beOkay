import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/soft_card.dart';
import '../application/devices_controller.dart';
import '../domain/device_status.dart';
import '../domain/heart_rate.dart';
import 'devices_screen.dart' show agoText;
import 'simulation_panel.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String clock(DateTime t) =>
    '${_two(t.toLocal().hour)}:${_two(t.toLocal().minute)}';
String shortDate(String iso) =>
    '${iso.substring(8, 10)}/${iso.substring(5, 7)}';

List<(DateTime, DateTime)> dataGaps(
  List<HeartRateBucketView> buckets, {
  Duration minimum = const Duration(minutes: 30),
}) {
  final sorted = [...buckets]..sort((a, b) => a.start.compareTo(b.start));
  final out = <(DateTime, DateTime)>[];
  for (var i = 1; i < sorted.length; i++) {
    final from = sorted[i - 1].start.add(const Duration(minutes: 5));
    final to = sorted[i].start;
    if (to.difference(from) >= minimum) out.add((from, to));
  }
  return out;
}

class HeartRateScreen extends ConsumerStatefulWidget {
  const HeartRateScreen({super.key});
  @override
  ConsumerState<HeartRateScreen> createState() => _HeartRateScreenState();
}

class _HeartRateScreenState extends ConsumerState<HeartRateScreen> {
  int days = 7;
  String? selected;

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(heartRateSummaryProvider(days));
    return PageScaffold(
      title: 'Detak jantung',
      onRefresh: () async {
        ref.invalidate(heartRateSummaryProvider);
        ref.invalidate(heartRateDayProvider);
        await ref.read(heartRateSummaryProvider(days).future);
      },
      children: [
        const SimulationBanner(),
        AsyncBody<HeartRateSummary>(
          value: summary,
          onRetry: () => ref.invalidate(heartRateSummaryProvider),
          data: (s) => _Body(
            summary: s,
            days: days,
            selected: selected ?? s.series.last.date,
            onDays: (d) => setState(() {
              days = d;
              selected = null;
            }),
            onSelect: (d) => setState(() => selected = d),
          ),
        ),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.summary,
    required this.days,
    required this.selected,
    required this.onDays,
    required this.onSelect,
  });
  final HeartRateSummary summary;
  final int days;
  final String selected;
  final ValueChanged<int> onDays;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = summary.latest;
    final detail = ref.watch(heartRateDayProvider(selected));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!summary.heartRateEnabled && !summary.restingEnabled)
          const InfoCard(
            text:
                'Detak jantung belum dinyalakan. Nyalakan di Perangkat & Kesehatan, lalu sinkronkan.',
          ),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PENGUKURAN TERAKHIR', style: AppTypography.overline),
              const SizedBox(height: AppSpacing.xs),
              if (latest == null)
                Text(
                  'Belum ada pengukuran. Ini bukan 0 bpm; datanya memang belum masuk.',
                  style: AppTypography.secondary,
                )
              else ...[
                Semantics(
                  label:
                      'Pengukuran terakhir ${latest.bpm} denyut per menit, ${agoText(latest.windowStart)}',
                  excludeSemantics: true,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('${latest.bpm}', style: AppTypography.metricLarge),
                      const SizedBox(width: 6),
                      Text('bpm', style: AppTypography.secondary),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Rata-rata jendela 5 menit pukul ${clock(latest.windowStart)} · ${agoText(latest.windowStart)} · ${originLabel(latest.origin ?? 'tidak diketahui')}',
                  style: AppTypography.caption,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    if (summary.freshness == 'STALE')
                      const StatusBadge(
                        label: 'Data sudah lama',
                        tone: InfoTone.warning,
                      ),
                    if (latest.simulated)
                      const StatusBadge(
                        label: 'DATA SIMULASI',
                        tone: InfoTone.warning,
                      ),
                  ],
                ),
              ],
              const Divider(height: AppSpacing.lg),
              Text('DETAK JANTUNG ISTIRAHAT', style: AppTypography.overline),
              const SizedBox(height: AppSpacing.xxs),
              if (summary.restingLatest == null)
                Text(
                  'Belum ada data istirahat dari perangkat.',
                  style: AppTypography.secondary,
                )
              else
                Text(
                  '${summary.restingLatest!.bpm} bpm · ${agoText(summary.restingLatest!.measuredAt)}',
                  style: AppTypography.bodyStrong,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text('Tren harian', style: AppTypography.heading),
              ),
            ),
            for (final d in const [7, 14, 30])
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(
                  label: Text('$d hari'),
                  selected: days == d,
                  onSelected: (_) => onDays(d),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        SoftCard(
          child: summary.hasData
              ? SizedBox(
                  height: 180,
                  child: HeartRateRangeChart(
                    series: summary.series,
                    selected: selected,
                    onSelect: onSelect,
                  ),
                )
              : Text(
                  'Belum ada data pada ${summary.days} hari terakhir.',
                  style: AppTypography.secondary,
                ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(summary.methodology, style: AppTypography.caption),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          header: true,
          child: Text(
            'Rincian ${shortDate(selected)}',
            style: AppTypography.heading,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AsyncBody<HeartRateDayDetail>(
          value: detail,
          onRetry: () => ref.invalidate(heartRateDayProvider),
          skeletonRows: 1,
          data: (d) => _DayDetail(detail: d),
        ),
        const SizedBox(height: AppSpacing.md),
        InfoCard(tone: InfoTone.neutral, text: summary.notice),
      ],
    );
  }
}

class _DayDetail extends StatelessWidget {
  const _DayDetail({required this.detail});
  final HeartRateDayDetail detail;

  @override
  Widget build(BuildContext context) {
    final s = detail.summary;
    final gaps = dataGaps(detail.buckets);
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!s.hasData)
            Text(
              'Tidak ada data pada hari ini.',
              style: AppTypography.secondary,
            )
          else ...[
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                _Stat('Terendah', s.minimum == null ? '—' : '${s.minimum}'),
                _Stat(
                  'Rata-rata',
                  s.average == null ? '—' : s.average!.toStringAsFixed(1),
                ),
                _Stat('Tertinggi', s.maximum == null ? '—' : '${s.maximum}'),
                _Stat('Istirahat', s.resting == null ? '—' : '${s.resting}'),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              s.insufficient
                  ? 'Sampel belum cukup untuk ringkasan (${s.sampleCount}).'
                  : '${s.sampleCount} sampel di ${s.observedBuckets} jendela 5 menit · cakupan ${(s.coverage * 100).round()}%',
              style: AppTypography.caption,
            ),
            if (detail.buckets.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 120,
                child: HeartRateDayChart(buckets: detail.buckets),
              ),
            ],
            if (gaps.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Tanpa data: ${gaps.take(4).map((g) => '${clock(g.$1)}–${clock(g.$2)}').join(', ')}${gaps.length > 4 ? ' dan ${gaps.length - 4} lainnya' : ''}',
                style: AppTypography.caption,
              ),
            ],
            if (s.needsReview) ...[
              const SizedBox(height: AppSpacing.xs),
              const StatusBadge(
                label: 'Ada nilai tidak lazim, perlu diperiksa',
                tone: InfoTone.warning,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label $value',
    excludeSemantics: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption),
        Text(value, style: AppTypography.metric),
      ],
    ),
  );
}

class HeartRateRangeChart extends StatelessWidget {
  const HeartRateRangeChart({
    super.key,
    required this.series,
    required this.selected,
    required this.onSelect,
  });
  final List<HeartRateDay> series;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final label = [
      for (final d in series)
        if (d.hasData && d.minimum != null)
          '${shortDate(d.date)}: ${d.minimum} sampai ${d.maximum}'
        else
          '${shortDate(d.date)}: tanpa data',
    ].join('. ');
    return Semantics(
      label: 'Grafik rentang detak jantung harian. $label',
      child: LayoutBuilder(
        builder: (context, c) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (t) {
            final i = (t.localPosition.dx / c.maxWidth * series.length)
                .floor()
                .clamp(0, series.length - 1);
            onSelect(series[i].date);
          },
          child: CustomPaint(
            size: Size(c.maxWidth, c.maxHeight),
            painter: _RangePainter(
              series,
              selected,
              AppColors.primary,
              AppColors.border,
              AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _RangePainter extends CustomPainter {
  _RangePainter(this.series, this.selected, this.bar, this.grid, this.text);
  final List<HeartRateDay> series;
  final String selected;
  final Color bar, grid, text;

  @override
  void paint(Canvas canvas, Size size) {
    final values = [
      for (final d in series)
        if (d.minimum != null) ...[d.minimum!, d.maximum!],
    ];
    if (values.isEmpty) return;
    final lo = (values.reduce((a, b) => a < b ? a : b) - 5).clamp(20, 300);
    final hi = (values.reduce((a, b) => a > b ? a : b) + 5).clamp(20, 300);
    final range = (hi - lo).toDouble().clamp(10, 300);
    const bottom = 22.0;
    final h = size.height - bottom;
    double y(num v) => h - (v - lo) / range * h;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final t in [lo, (lo + hi) / 2, hi]) {
      canvas.drawLine(Offset(0, y(t)), Offset(size.width, y(t)), gridPaint);
      _label(canvas, t.round().toString(), Offset(0, y(t) - 12), text);
    }
    final slot = size.width / series.length;
    for (var i = 0; i < series.length; i++) {
      final d = series[i];
      final cx = slot * i + slot / 2;
      if (d.date == selected) {
        canvas.drawRect(
          Rect.fromLTWH(slot * i, 0, slot, size.height),
          Paint()..color = bar.withValues(alpha: 0.08),
        );
      }
      if (series.length <= 14 || i % 3 == 0) {
        _label(canvas, shortDate(d.date), Offset(cx - 14, h + 4), text);
      }
      if (d.minimum == null) continue;
      final w = (slot * 0.5).clamp(4.0, 18.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(cx - w / 2, y(d.maximum!), cx + w / 2, y(d.minimum!)),
          const Radius.circular(4),
        ),
        Paint()..color = bar.withValues(alpha: 0.35),
      );
      if (d.average != null) {
        canvas.drawCircle(Offset(cx, y(d.average!)), 3.5, Paint()..color = bar);
      }
      if (d.resting != null) {
        canvas.drawCircle(
          Offset(cx, y(d.resting!)),
          3,
          Paint()
            ..color = text
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  void _label(Canvas canvas, String s, Offset at, Color color) {
    final p = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: 10, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_RangePainter old) =>
      old.series != series || old.selected != selected;
}

class HeartRateDayChart extends StatelessWidget {
  const HeartRateDayChart({super.key, required this.buckets});
  final List<HeartRateBucketView> buckets;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Grafik pengukuran per 5 menit, ${buckets.length} jendela. Titik tidak dihubungkan karena ada jeda tanpa data.',
    child: CustomPaint(
      painter: _DayPainter(
        buckets,
        AppColors.primary,
        AppColors.border,
        AppColors.textSecondary,
      ),
      size: Size.infinite,
    ),
  );
}

class _DayPainter extends CustomPainter {
  _DayPainter(this.buckets, this.bar, this.grid, this.text);
  final List<HeartRateBucketView> buckets;
  final Color bar, grid, text;

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) return;
    final local = buckets.map((b) => b.start.toLocal()).toList();
    final dayStart = DateTime(
      local.first.year,
      local.first.month,
      local.first.day,
    );
    final lo = (buckets.map((b) => b.min).reduce((a, b) => a < b ? a : b) - 5)
        .clamp(20, 300);
    final hi = (buckets.map((b) => b.max).reduce((a, b) => a > b ? a : b) + 5)
        .clamp(20, 300);
    final range = (hi - lo).toDouble().clamp(10, 300);
    const bottom = 18.0;
    final h = size.height - bottom;
    double y(num v) => h - (v - lo) / range * h;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h), Offset(size.width, h), gridPaint);
    for (final hour in [0, 6, 12, 18, 24]) {
      final x = hour / 24 * size.width;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, h),
        gridPaint..color = grid.withValues(alpha: 0.5),
      );
      final p = TextPainter(
        text: TextSpan(
          text: '${_two(hour % 24)}:00',
          style: TextStyle(fontSize: 10, color: text),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(canvas, Offset((x - 12).clamp(0, size.width - 28), h + 3));
    }
    for (var i = 0; i < buckets.length; i++) {
      final b = buckets[i];
      final minutes = local[i].difference(dayStart).inMinutes;
      final x = (minutes / 1440 * size.width).clamp(1.0, size.width - 1);
      canvas.drawLine(
        Offset(x, y(b.max)),
        Offset(x, y(b.min)),
        Paint()
          ..color = (b.needsReview ? AppColors.sparkAmber : bar).withValues(
            alpha: 0.45,
          )
          ..strokeWidth = 2.5,
      );
      canvas.drawCircle(
        Offset(x, y(b.avg)),
        2.2,
        Paint()..color = b.needsReview ? AppColors.sparkAmber : bar,
      );
    }
  }

  @override
  bool shouldRepaint(_DayPainter old) => old.buckets != buckets;
}
