import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/ids/record_id.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/account_scoped_repository.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/discard_guard.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../today/application/today_controller.dart';
import '../application/activity_controller.dart';
import '../data/activity_models.dart';

class ActivityFormScreen extends ConsumerStatefulWidget {
  const ActivityFormScreen({super.key, this.initial});
  final ActivityRecord? initial;
  @override
  ConsumerState<ActivityFormScreen> createState() => _ActivityFormState();
}

class _ActivityFormState extends ConsumerState<ActivityFormScreen> {
  final form = GlobalKey<FormState>();
  final recordId = newRecordId();
  late final duration = TextEditingController(
    text: widget.initial?.durationMinutes.toString(),
  );
  late final distance = TextEditingController(
    text: widget.initial?.distanceKm?.toString(),
  );
  late final steps = TextEditingController(
    text: widget.initial?.steps?.toString(),
  );
  late final notes = TextEditingController(text: widget.initial?.notes);
  final reason = TextEditingController();
  late String type = widget.initial?.activityType ?? 'walking',
      intensity = widget.initial?.reportedIntensity ?? 'unknown';
  late DateTime start =
      widget.initial?.startedAt.toLocal() ??
      DateTime.now().subtract(const Duration(minutes: 30));
  late bool review = widget.initial?.qualityStatus == 'needs_review';
  bool dirty = false, busy = false, uncertain = false, conflict = false;
  String? error;
  @override
  void dispose() {
    duration.dispose();
    distance.dispose();
    steps.dispose();
    notes.dispose();
    reason.dispose();
    super.dispose();
  }

  void changed(String _) => setState(() => dirty = true);
  Future<void> pickTime() async {
    final day = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start),
    );
    if (time != null && mounted) {
      setState(() {
        start = DateTime(day.year, day.month, day.day, time.hour, time.minute);
        dirty = true;
      });
    }
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    if (start
        .add(Duration(minutes: int.parse(duration.text.trim())))
        .isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      setState(
        () => error =
            'Catat sesi yang sudah selesai. Periksa waktu mulai dan durasi.',
      );
      return;
    }
    final repo = ref.read(activityRepositoryProvider);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final saved = await repo.save({
        if (widget.initial == null) 'id': recordId,
        if (widget.initial != null) ...{
          'expectedVersion': widget.initial!.version,
          'reason': reason.text.trim(),
        },
        'activityType': type,
        'startedAt': start.toUtc().toIso8601String(),
        'durationMinutes': int.parse(duration.text.trim()),
        'distanceKm': distance.text.trim().isEmpty
            ? null
            : num.parse(distance.text.trim().replaceAll(',', '.')),
        'steps': steps.text.trim().isEmpty
            ? null
            : int.parse(steps.text.trim()),
        'reportedIntensity': intensity,
        'source': 'manual',
        'qualityStatus': review ? 'needs_review' : 'user_reported',
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
      }, id: widget.initial?.id);
      if (!mounted || !repo.isCurrentAccount()) return;
      ref.invalidate(todayProvider);
      ref.invalidate(activityProvider(saved.id));
      ref.invalidate(activityPageProvider);
      ref.invalidate(activityDayProvider);
      ref.invalidate(activityWeekProvider);
      setState(() {
        dirty = false;
        uncertain = false;
      });
      context.go('${Routes.activities}/${saved.id}');
    } on QueuedOffline {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(queuedOfflineMessage)));
        setState(() => dirty = false);
        context.go(Routes.activities);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = messageFor(e);
          conflict =
              e is ApiException &&
              (e.code == 'VERSION_CONFLICT' ||
                  e.code == 'IDEMPOTENCY_CONFLICT');
          uncertain =
              conflict ||
              (e is ApiException && (e.isNetwork || e.status >= 500));
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = busy || uncertain;
    final minutes = int.tryParse(duration.text.trim());
    return DiscardGuard(
      dirty: dirty,
      child: PageScaffold(
        title: widget.initial == null ? 'Catat aktivitas' : 'Koreksi aktivitas',
        children: [
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sesi yang sudah selesai · dilaporkan sendiri.',
                  style: AppTypography.secondary,
                ),
                const SizedBox(height: 16),
                Text('Jenis aktivitas', style: AppTypography.title),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in activityTypes.entries)
                      PillChip(
                        label: entry.value,
                        selected: type == entry.key,
                        onTap: locked
                            ? null
                            : () => setState(() {
                                type = entry.key;
                                dirty = true;
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                PillButton(
                  label:
                      'Mulai: ${DateFormat('d MMM y, HH:mm', 'id_ID').format(start)}',
                  kind: PillButtonKind.secondary,
                  onPressed: locked ? null : pickTime,
                ),
                const SizedBox(height: 8),
                Text(
                  'Zona waktu perangkat: ${start.timeZoneName}.',
                  style: AppTypography.secondary,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Durasi (menit)',
                  hint: 'mis. 30',
                  controller: duration,
                  enabled: !locked,
                  keyboardType: TextInputType.number,
                  validator: validateActivityDuration,
                  onChanged: changed,
                ),
                const SizedBox(height: 8),
                Text(
                  minutes != null && minutes >= 1 && minutes <= 1440
                      ? 'Selesai: ${DateFormat('d MMM y, HH:mm', 'id_ID').format(start.add(Duration(minutes: minutes)))}'
                      : 'Waktu selesai dihitung dari waktu mulai dan durasi.',
                ),
                const SizedBox(height: 24),
                AppTextField(
                  label: 'Jarak (km, opsional)',
                  hint: 'mis. 2.5',
                  controller: distance,
                  enabled: !locked,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) => validateActivityMetric(v, steps: false),
                  onChanged: changed,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Langkah (opsional)',
                  hint: 'mis. 4000',
                  controller: steps,
                  enabled: !locked,
                  keyboardType: TextInputType.number,
                  validator: (v) => validateActivityMetric(v, steps: true),
                  onChanged: changed,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Kosongkan bila tidak diketahui. Nilai tidak diisi otomatis.',
                ),
                const SizedBox(height: 24),
                Text(
                  'Intensitas yang kamu rasakan',
                  style: AppTypography.title,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in activityIntensities.entries)
                      PillChip(
                        label: entry.value,
                        selected: intensity == entry.key,
                        onTap: locked
                            ? null
                            : () => setState(() {
                                intensity = entry.key;
                                dirty = true;
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tandai untuk ditinjau'),
                  subtitle: const Text(
                    'Tetap disimpan; tidak masuk total durasi ringkasan.',
                  ),
                  value: review,
                  onChanged: locked
                      ? null
                      : (v) => setState(() {
                          review = v!;
                          dirty = true;
                        }),
                ),
                AppTextField(
                  label: 'Catatan (opsional)',
                  hint: 'mis. jalan sore di taman',
                  controller: notes,
                  maxLength: 2000,
                  enabled: !locked,
                  onChanged: changed,
                ),
                if (widget.initial != null) ...[
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Alasan koreksi',
                    hint: 'mis. durasi salah',
                    controller: reason,
                    maxLength: 300,
                    enabled: !locked,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Isi alasan koreksi.'
                        : null,
                    onChanged: changed,
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Tanpa koneksi, catatan baru disimpan di perangkat dan dikirim nanti. Koreksi perlu koneksi.',
                ),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  ErrorBanner(error!),
                ],
                if (uncertain) ...[
                  const SizedBox(height: 12),
                  Text(
                    conflict
                        ? 'Catatan berubah. Tinjau versi terbaru sebelum mengoreksi.'
                        : 'Status simpan belum pasti. Coba ulang dengan isi yang sama atau periksa riwayat.',
                  ),
                  TextButton(
                    onPressed: () {
                      final id = widget.initial?.id ?? recordId;
                      ref.invalidate(activityProvider(id));
                      context.go(
                        conflict
                            ? '${Routes.activities}/$id'
                            : Routes.activities,
                      );
                    },
                    child: Text(
                      conflict ? 'Muat ulang catatan' : 'Periksa riwayat',
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                PillButton(
                  label: widget.initial == null
                      ? 'Simpan aktivitas'
                      : 'Simpan koreksi',
                  loading: busy,
                  onPressed: conflict ? null : save,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
