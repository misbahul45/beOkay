import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/a11y/announce.dart';
import '../../core/analytics/usage_tracker.dart';
import '../../core/ids/record_id.dart';
import '../../core/offline/offline_queue.dart';
import '../../core/offline/sync_controller.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/info_card.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/pill_button.dart';

const guestDays = 7;
const guestAccount = 'guest';
const _startedKey = 'beokay.guest.startedAt';

class GuestState {
  const GuestState({
    this.loaded = false,
    this.startedAt,
    this.records = const [],
  });
  final bool loaded;
  final DateTime? startedAt;
  final List<QueuedOperation> records;

  bool get started => startedAt != null;
  int daysLeft(DateTime now) {
    if (startedAt == null) return guestDays;
    final used = now.difference(startedAt!).inHours / 24;
    return (guestDays - used).ceil().clamp(0, guestDays);
  }

  bool expired(DateTime now) => started && daysLeft(now) == 0;
}

class GuestController extends Notifier<GuestState> {
  KeyValueStore get _store => ref.read(keyValueStoreProvider);
  OfflineQueue get _queue => OfflineQueue(_store, guestAccount);

  @override
  GuestState build() {
    unawaited(_load());
    return const GuestState();
  }

  Future<void> _load() async {
    final raw = await _store.read(_startedKey);
    final records = await _queue.load();
    if (!ref.mounted) return;
    state = GuestState(
      loaded: true,
      startedAt: raw == null ? null : DateTime.tryParse(raw),
      records: records,
    );
  }

  Future<void> start([DateTime? now]) async {
    if (state.started) return;
    final at = (now ?? DateTime.now()).toUtc();
    await _store.write(_startedKey, at.toIso8601String());
    await _load();
  }

  Future<bool> add(String domain, Map<String, dynamic> payload) async {
    if (state.expired(DateTime.now())) return false;
    await _queue.add(
      QueuedOperation(
        operationId: newRecordId(),
        domain: domain,
        recordId: newRecordId(),
        operationType: 'create',
        payload: payload,
        createdAt: DateTime.now(),
      ),
    );
    await _load();
    return true;
  }

  Future<void> clear() async {
    await _queue.clear();
    await _store.delete(_startedKey);
    await _load();
  }

  Future<int> migrateTo(
    Future<void> Function(QueuedOperation op) enqueue,
  ) async {
    final ops = await _queue.load();
    for (final op in ops) {
      await enqueue(op);
    }
    await clear();
    return ops.length;
  }
}

final guestControllerProvider = NotifierProvider<GuestController, GuestState>(
  GuestController.new,
);

String guestRecordLabel(QueuedOperation op) {
  final p = op.payload;
  return switch (op.domain) {
    'glucose' => 'Glukosa ${_num(p['originalValue'])} ${p['originalUnit']}',
    'meal' =>
      ((p['items'] as List?)?.isNotEmpty ?? false)
          ? ((p['items'] as List).first as Map)['name'] as String
          : 'Makan',
    'activity' =>
      '${_activityLabel(p['activityType'] as String?)} ${p['durationMinutes']} menit',
    _ => op.label,
  };
}

String _num(Object? v) => v is num
    ? (v % 1 == 0 ? v.toInt().toString() : v.toString().replaceAll('.', ','))
    : '$v';

String _activityLabel(String? t) => switch (t) {
  'walking' => 'Jalan kaki',
  'cycling' => 'Bersepeda',
  'running' => 'Lari',
  'strength' => 'Latihan kekuatan',
  _ => 'Aktivitas',
};

DateTime? _recordTime(QueuedOperation op) {
  final p = op.payload;
  final raw = (p['measuredAt'] ?? p['consumedAt'] ?? p['startedAt']) as String?;
  return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
}

class GuestHomeScreen extends ConsumerStatefulWidget {
  const GuestHomeScreen({super.key});
  @override
  ConsumerState<GuestHomeScreen> createState() => _GuestHomeScreenState();
}

class _GuestHomeScreenState extends ConsumerState<GuestHomeScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(guestControllerProvider.notifier).start());
  }

  Future<void> addRecord(String kind) async {
    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => GuestRecordSheet(kind: kind),
    );
    if (payload == null) return;
    final ok = await ref
        .read(guestControllerProvider.notifier)
        .add(kind, payload);
    if (!mounted) return;
    announce(
      context,
      ok
          ? 'Tersimpan di ponsel ini'
          : 'Masa coba berakhir. Buat akun untuk lanjut mencatat.',
    );
  }

  Future<void> leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus catatan mode coba?'),
        content: const Text(
          'Catatan yang tersimpan di ponsel ini akan dihapus dan tidak bisa dikembalikan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(guestControllerProvider.notifier).clear();
    if (mounted) context.go(Routes.welcome);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(guestControllerProvider);
    final now = DateTime.now();
    final left = s.daysLeft(now);
    final expired = s.expired(now);
    final fmt = DateFormat('EEE d MMM HH.mm', 'id_ID');
    final sorted = [...s.records]
      ..sort(
        (a, b) => (_recordTime(b) ?? b.createdAt).compareTo(
          _recordTime(a) ?? a.createdAt,
        ),
      );
    return PageScaffold(
      title: 'Mode coba',
      onBack: () => context.go(Routes.welcome),
      children: [
        InfoCard(
          tone: InfoTone.warning,
          text: expired
              ? 'Masa coba 7 hari sudah berakhir. Catatanmu masih ada di ponsel ini. Buat akun untuk menyimpannya.'
              : 'Sisa $left hari. Catatan tersimpan hanya di ponsel ini, terenkripsi. Buat akun untuk menyimpannya dan melihat ringkasan.',
        ),
        const SizedBox(height: AppSpacing.md),
        if (sorted.isEmpty)
          Text(
            'Belum ada catatan. Mulai dari satu catatan kecil.',
            style: AppTypography.secondary,
          ),
        for (final op in sorted)
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: ListTile(
              leading: Icon(switch (op.domain) {
                'glucose' => Icons.water_drop_outlined,
                'meal' => Icons.restaurant_outlined,
                _ => Icons.directions_walk_rounded,
              }),
              title: Text(guestRecordLabel(op)),
              subtitle: Text(
                _recordTime(op) == null ? '' : fmt.format(_recordTime(op)!),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (kind, label) in [
              ('glucose', '+ Glukosa'),
              ('meal', '+ Makan'),
              ('activity', '+ Aktivitas'),
            ])
              OutlinedButton(
                onPressed: expired ? null : () => addRecord(kind),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                child: Text(label),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        PillButton(
          label: 'Buat akun dan simpan',
          onPressed: () => context.go(Routes.register),
        ),
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: TextButton(
            onPressed: () => context.go(Routes.login),
            child: const Text('Sudah punya akun? Masuk'),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: leave,
            child: const Text('Hapus catatan mode coba'),
          ),
        ),
      ],
    );
  }
}

class GuestRecordSheet extends StatefulWidget {
  const GuestRecordSheet({super.key, required this.kind});
  final String kind;
  @override
  State<GuestRecordSheet> createState() => _GuestRecordSheetState();
}

class _GuestRecordSheetState extends State<GuestRecordSheet> {
  final text = TextEditingController();
  String unit = 'mg/dL';
  String context_ = 'fasting';
  String category = 'lunch';
  String activity = 'walking';
  String? error;

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  void save() {
    final now = DateTime.now().toUtc().toIso8601String();
    final raw = text.text.trim().replaceAll(',', '.');
    Map<String, dynamic>? payload;
    switch (widget.kind) {
      case 'glucose':
        final v = double.tryParse(raw);
        final ok =
            v != null &&
            (unit == 'mg/dL' ? v >= 20 && v <= 600 : v >= 1.1 && v <= 33.3);
        if (ok) {
          payload = {
            'originalValue': double.parse(
              v.toStringAsFixed(unit == 'mg/dL' ? 0 : 1),
            ),
            'originalUnit': unit,
            'measuredAt': now,
            'mealContext': context_,
          };
        } else {
          error = unit == 'mg/dL' ? 'Isi angka 20–600.' : 'Isi angka 1,1–33,3.';
        }
      case 'meal':
        if (raw.length >= 2 && raw.length <= 120) {
          payload = {
            'category': category,
            'consumedAt': now,
            'notes': null,
            'items': [
              {'name': text.text.trim(), 'quantity': 1, 'unit': 'portion'},
            ],
          };
        } else {
          error = 'Tulis nama makanan.';
        }
      default:
        final m = int.tryParse(raw);
        if (m != null && m >= 1 && m <= 600) {
          payload = {
            'activityType': activity,
            'startedAt': DateTime.now()
                .subtract(Duration(minutes: m))
                .toUtc()
                .toIso8601String(),
            'durationMinutes': m,
          };
        } else {
          error = 'Isi lama aktivitas dalam menit.';
        }
    }
    if (payload != null) {
      Navigator.pop(context, payload);
    } else {
      setState(() {});
    }
  }

  Widget chips(
    List<(String, String)> options,
    String value,
    ValueChanged<String> onPick,
  ) => Wrap(
    spacing: 8,
    children: [
      for (final (v, l) in options)
        ChoiceChip(
          label: Text(l),
          selected: value == v,
          onSelected: (_) => setState(() => onPick(v)),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.kind) {
      'glucose' => 'Catat glukosa',
      'meal' => 'Catat makan',
      _ => 'Catat aktivitas',
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.title),
          const SizedBox(height: 8),
          TextField(
            controller: text,
            autofocus: true,
            keyboardType: widget.kind == 'meal'
                ? TextInputType.text
                : const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: widget.kind == 'meal'
                ? null
                : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              labelText: switch (widget.kind) {
                'glucose' => 'Nilai glukosa',
                'meal' => 'Makanan',
                _ => 'Lama (menit)',
              },
              errorText: error,
            ),
          ),
          const SizedBox(height: 8),
          if (widget.kind == 'glucose') ...[
            chips(
              const [('mg/dL', 'mg/dL'), ('mmol/L', 'mmol/L')],
              unit,
              (v) => unit = v,
            ),
            chips(
              const [
                ('fasting', 'Puasa'),
                ('before_meal', 'Sebelum makan'),
                ('after_meal', 'Setelah makan'),
              ],
              context_,
              (v) => context_ = v,
            ),
          ],
          if (widget.kind == 'meal')
            chips(
              const [
                ('breakfast', 'Sarapan'),
                ('lunch', 'Makan siang'),
                ('dinner', 'Makan malam'),
                ('snack', 'Camilan'),
              ],
              category,
              (v) => category = v,
            ),
          if (widget.kind == 'activity')
            chips(
              const [
                ('walking', 'Jalan kaki'),
                ('cycling', 'Bersepeda'),
                ('strength', 'Latihan kekuatan'),
                ('other', 'Lainnya'),
              ],
              activity,
              (v) => activity = v,
            ),
          const SizedBox(height: 12),
          PillButton(label: 'Simpan di ponsel', onPressed: save),
        ],
      ),
    );
  }
}

class GuestImportCard extends ConsumerStatefulWidget {
  const GuestImportCard({super.key});
  @override
  ConsumerState<GuestImportCard> createState() => _GuestImportCardState();
}

class _GuestImportCardState extends ConsumerState<GuestImportCard> {
  bool busy = false;

  Future<void> migrate() async {
    setState(() => busy = true);
    final sync = ref.read(syncControllerProvider.notifier);
    final n = await ref
        .read(guestControllerProvider.notifier)
        .migrateTo(sync.enqueue);
    ref
        .read(usageTrackerProvider)
        .track('guest_records_migrated', meta: {'via': 'guest', 'count': n});
    unawaited(sync.flush());
    if (mounted) {
      setState(() => busy = false);
      announce(context, '$n catatan dipindahkan ke akunmu');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(guestControllerProvider);
    if (!s.loaded || s.records.isEmpty) return const SizedBox.shrink();
    final n = s.records.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InfoCard(
        icon: Icons.move_down_rounded,
        title: 'Ada $n catatan dari mode coba di ponsel ini',
        text:
            'Pindahkan ke akun ini? Catatan dikirim lewat sinkron biasa dan tersimpan di akunmu.',
        action: Wrap(
          spacing: 8,
          children: [
            PillButton(
              label: 'Pindahkan $n catatan',
              expand: false,
              loading: busy,
              onPressed: migrate,
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => ref.read(guestControllerProvider.notifier).clear(),
              child: const Text('Hapus dari ponsel'),
            ),
          ],
        ),
      ),
    );
  }
}
