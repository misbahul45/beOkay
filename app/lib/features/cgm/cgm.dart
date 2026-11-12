import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/a11y/announce.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/choice_chips.dart';
import '../../core/widgets/info_card.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/pill_button.dart';

class CgmBands {
  CgmBands.fromJson(Map<String, dynamic> j)
    : veryLow = j['veryLow'] as num,
      low = j['low'] as num,
      inRange = j['inRange'] as num,
      high = j['high'] as num,
      veryHigh = j['veryHigh'] as num;
  final num veryLow, low, inRange, high, veryHigh;
}

class CgmSummary {
  CgmSummary.fromJson(Map<String, dynamic> j)
    : start = (j['period'] as Map)['start'] as String,
      end = (j['period'] as Map)['end'] as String,
      days = (j['days'] as num).toInt(),
      readings = (j['readings'] as num).toInt(),
      kindUsed = j['kindUsed'] as String?,
      coveragePct = j['coveragePct'] as num?,
      meanMgDl = j['meanMgDl'] as num?,
      meanMmolL = j['meanMmolL'] as num?,
      unit = (j['glucoseUnit'] as String?) ?? 'mg/dL',
      bands = j['bands'] == null
          ? null
          : CgmBands.fromJson(j['bands'] as Map<String, dynamic>),
      limitations = (j['limitations'] as List).cast<String>(),
      notice = j['notice'] as String;
  final String start, end, unit, notice;
  final String? kindUsed;
  final int days, readings;
  final num? coveragePct, meanMgDl, meanMmolL;
  final CgmBands? bands;
  final List<String> limitations;

  String get meanLabel {
    if (meanMgDl == null) return '–';
    return unit == 'mmol/L'
        ? '${meanMmolL!.toStringAsFixed(1).replaceAll('.', ',')} mmol/L'
        : '${meanMgDl!.round()} mg/dL';
  }
}

class CgmImport {
  CgmImport.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      fileName = j['fileName'] as String?,
      accepted = (j['rowsAccepted'] as num).toInt(),
      duplicate = (j['rowsDuplicate'] as num).toInt(),
      skipped = (j['rowsSkipped'] as num).toInt(),
      periodStart = j['periodStart'] == null
          ? null
          : DateTime.parse(j['periodStart'] as String).toLocal(),
      periodEnd = j['periodEnd'] == null
          ? null
          : DateTime.parse(j['periodEnd'] as String).toLocal(),
      createdAt = DateTime.parse(j['createdAt'] as String).toLocal();
  final String id;
  final String? fileName;
  final int accepted, duplicate, skipped;
  final DateTime? periodStart, periodEnd;
  final DateTime createdAt;
}

class CgmRepository {
  CgmRepository(this.api);
  final ApiClient api;

  Future<CgmImport> upload(
    String csv, {
    String? fileName,
    String dateOrder = 'auto',
  }) async {
    final q = Uri(
      queryParameters: {'fileName': ?fileName, 'dateOrder': dateOrder},
    ).query;
    return CgmImport.fromJson(
      (await api.postBytes(
        '/api/me/cgm/imports?$q',
        utf8.encode(csv),
        contentType: 'text/csv',
        timeout: const Duration(seconds: 60),
      )).object,
    );
  }

  Future<List<CgmImport>> imports() async => [
    for (final i
        in (await api.get('/api/me/cgm/imports')).object['items'] as List)
      CgmImport.fromJson(i as Map<String, dynamic>),
  ];

  Future<void> remove(String id) =>
      api.send('DELETE', '/api/me/cgm/imports/$id');

  Future<CgmSummary> summary(int days) async => CgmSummary.fromJson(
    (await api.get('/api/me/cgm/summary?days=$days')).object,
  );
}

typedef CsvPicker = Future<({String name, String text})?> Function();

Future<({String name, String text})?> _pickCsv() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['csv', 'txt'],
  );
  if (files.isEmpty) return null;
  final f = files.first;
  if ((f.lengthSync() ?? 0) > 4 * 1024 * 1024) {
    throw const ApiException(
      status: 413,
      code: 'PAYLOAD_TOO_LARGE',
      message: 'Berkas terlalu besar (maksimal 4 MB).',
    );
  }
  return (
    name: f.name,
    text: utf8.decode(await f.readAsBytes(), allowMalformed: true),
  );
}

final cgmRepositoryProvider = Provider<CgmRepository>(
  (ref) => CgmRepository(ref.watch(apiClientProvider)),
);
final csvPickerProvider = Provider<CsvPicker>((ref) => _pickCsv);
final cgmSummaryProvider = FutureProvider.autoDispose.family<CgmSummary, int>(
  (ref, days) => ref.watch(cgmRepositoryProvider).summary(days),
);
final cgmImportsProvider = FutureProvider.autoDispose<List<CgmImport>>(
  (ref) => ref.watch(cgmRepositoryProvider).imports(),
);

class CgmScreen extends ConsumerStatefulWidget {
  const CgmScreen({super.key});
  @override
  ConsumerState<CgmScreen> createState() => _CgmScreenState();
}

class _CgmScreenState extends ConsumerState<CgmScreen> {
  int days = 14;
  bool busy = false;
  CgmImport? last;
  String? error;

  Future<void> upload({
    ({String name, String text})? file,
    String? order,
  }) async {
    final picked = file ?? await ref.read(csvPickerProvider)();
    if (picked == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await ref
          .read(cgmRepositoryProvider)
          .upload(
            picked.text,
            fileName: picked.name,
            dateOrder: order ?? 'auto',
          );
      setState(() => last = r);
      ref.invalidate(cgmSummaryProvider);
      ref.invalidate(cgmImportsProvider);
      if (mounted) announce(context, 'Impor selesai');
    } on ApiException catch (e) {
      if (e.code == 'CGM_DATE_ORDER_AMBIGUOUS' && mounted) {
        setState(() => busy = false);
        final chosen = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Bagaimana tanggal ditulis?'),
            content: const Text(
              'Contoh 03-04: apakah itu 3 April (hari-bulan) atau 4 Maret (bulan-hari)? Lihat pengaturan negara di LibreView.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, 'DMY'),
                child: const Text('Hari-bulan'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, 'MDY'),
                child: const Text('Bulan-hari'),
              ),
            ],
          ),
        );
        if (chosen != null) return upload(file: picked, order: chosen);
      } else {
        setState(() => error = messageFor(e));
      }
    } catch (e) {
      setState(() => error = messageFor(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(cgmSummaryProvider(days));
    final imports = ref.watch(cgmImportsProvider);
    return PageScaffold(
      title: 'Sensor glukosa (CGM)',
      children: [
        const InfoCard(
          tone: InfoTone.neutral,
          text:
              'Ekspor data dari LibreView (CSV), lalu pilih berkasnya di sini. Berkas dibaca di server beOkay dan disimpan terpisah dari catatan glukosa jari.',
        ),
        const SizedBox(height: AppSpacing.sm),
        PillButton(
          label: 'Pilih berkas CSV',
          icon: Icons.upload_file_outlined,
          loading: busy,
          onPressed: () => upload(),
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          InfoCard(tone: InfoTone.error, text: error!),
        ],
        if (last case final r?) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoCard(
            title: 'Impor selesai',
            text:
                '${r.accepted} bacaan diterima · ${r.duplicate} sudah ada · ${r.skipped} dilewati (kosong, LO/HI, atau bukan glukosa).',
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text('Ringkasan', style: AppTypography.heading),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final d in [14, 30, 90])
              PillChip(
                label: '$d hari',
                selected: days == d,
                onTap: () => setState(() => days = d),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        summary.when(
          loading: () => const SkeletonList(rows: 3),
          error: (e, _) => ErrorState(
            error: e,
            onRetry: () => ref.invalidate(cgmSummaryProvider(days)),
          ),
          data: (s) => CgmSummaryCard(summary: s),
        ),
        const SizedBox(height: AppSpacing.lg),
        imports.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (items) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (items.isNotEmpty)
                Text('Riwayat impor', style: AppTypography.title),
              for (final i in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(i.fileName ?? 'Berkas CSV'),
                  subtitle: Text(
                    '${i.accepted} bacaan${i.periodStart == null ? '' : ' · ${_d(i.periodStart!)} – ${_d(i.periodEnd!)}'}',
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      await ref.read(cgmRepositoryProvider).remove(i.id);
                      ref.invalidate(cgmImportsProvider);
                      ref.invalidate(cgmSummaryProvider);
                    },
                    child: const Text('Hapus'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _d(DateTime t) => '${t.day}/${t.month}';

class CgmSummaryCard extends StatelessWidget {
  const CgmSummaryCard({super.key, required this.summary});
  final CgmSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final b = s.bands;
    String pct(num v) =>
        '${v.toStringAsFixed(v % 1 == 0 ? 0 : 1).replaceAll('.', ',')}%';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${s.start} – ${s.end}', style: AppTypography.caption),
          if (b == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Belum ada data sensor pada periode ini.',
                style: AppTypography.secondary,
              ),
            )
          else ...[
            const SizedBox(height: 6),
            Text(
              'Waktu dalam rentang 70–180 mg/dL',
              style: AppTypography.bodyStrong,
            ),
            Semantics(
              label: 'Waktu dalam rentang ${pct(b.inRange)}',
              child: Text(
                pct(b.inRange),
                style: AppTypography.display.copyWith(color: AppColors.brand),
              ),
            ),
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 12,
                  child: Row(
                    children: [
                      for (final (v, c) in [
                        (b.veryLow, AppColors.errorForeground),
                        (b.low, AppColors.warningForeground),
                        (b.inRange, AppColors.brand),
                        (b.high, AppColors.sparkAmber),
                        (b.veryHigh, AppColors.warningForeground),
                      ])
                        if (v > 0)
                          Expanded(
                            flex: (v * 10).round().clamp(1, 1000),
                            child: ColoredBox(color: c),
                          ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            for (final (l, v) in [
              ('Di bawah 54', b.veryLow),
              ('54–69', b.low),
              ('70–180', b.inRange),
              ('181–250', b.high),
              ('Di atas 250', b.veryHigh),
            ])
              _row(l, pct(v)),
            _row('Rata-rata', s.meanLabel),
            _row(
              'Data terekam',
              s.coveragePct == null
                  ? 'hanya pindaian'
                  : '${pct(s.coveragePct!)} dari ${s.days} hari',
            ),
          ],
          for (final l in s.limitations)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(l, style: AppTypography.secondary),
            ),
          const SizedBox(height: 6),
          Text(s.notice, style: AppTypography.caption),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.body)),
        Text(value, style: AppTypography.bodyStrong),
      ],
    ),
  );
}
