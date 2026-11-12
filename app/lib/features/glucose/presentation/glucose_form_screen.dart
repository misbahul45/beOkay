import '../../../core/a11y/announce.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/ids/record_id.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/account_scoped_repository.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/discard_guard.dart';
import '../../../core/widgets/domain_style.dart';
import '../../../core/widgets/form_kit.dart';
import '../../../core/widgets/health_error.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../preferences/application/preferences_controller.dart';
import '../../today/application/today_controller.dart';
import '../application/glucose_controller.dart';
import '../data/glucose_models.dart';
import 'glucose_alert_card.dart';
import '../../../core/analytics/usage_tracker.dart';

class GlucoseFormScreen extends ConsumerWidget {
  const GlucoseFormScreen({super.key, this.initial});
  final GlucoseRecord? initial;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initial != null) {
      return _GlucoseForm(initial: initial, defaultUnit: initial!.originalUnit);
    }
    return ref
        .watch(preferencesControllerProvider)
        .when(
          loading: () => const PageScaffold(
            title: 'Catat glukosa',
            children: [SkeletonList()],
          ),
          error: (e, _) => PageScaffold(
            title: 'Catat glukosa',
            children: [
              HealthError(
                error: e,
                retry: () => ref.invalidate(preferencesControllerProvider),
              ),
            ],
          ),
          data: (p) => _GlucoseForm(defaultUnit: p.glucoseUnit.wire),
        );
  }
}

class _GlucoseForm extends ConsumerStatefulWidget {
  const _GlucoseForm({this.initial, required this.defaultUnit});
  final GlucoseRecord? initial;
  final String defaultUnit;
  @override
  ConsumerState<_GlucoseForm> createState() => _GlucoseFormState();
}

class _GlucoseFormState extends ConsumerState<_GlucoseForm> {
  final form = GlobalKey<FormState>();
  final recordId = newRecordId();
  final opened = DateTime.now();
  late final value = TextEditingController(
    text: widget.initial?.originalValue.toString(),
  );
  late final notes = TextEditingController(text: widget.initial?.notes);
  final reason = TextEditingController();
  late String unit = widget.initial?.originalUnit ?? widget.defaultUnit;
  late String mealContext = widget.initial?.mealContext ?? 'unknown';
  late DateTime time = widget.initial?.measuredAt.toLocal() ?? DateTime.now();
  late bool review = widget.initial?.qualityStatus == 'needs_review';
  bool dirty = false, busy = false, uncertain = false, conflict = false;
  String? error;
  @override
  void dispose() {
    value.dispose();
    notes.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> pickTime() async {
    final day = await showDatePicker(
      context: context,
      initialDate: time,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (day == null || !mounted) return;
    final clock = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(time),
    );
    if (clock != null && mounted) {
      setState(() {
        time = DateTime(day.year, day.month, day.day, clock.hour, clock.minute);
        dirty = true;
      });
    }
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    if (time.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      setState(() => error = 'Waktu pengukuran tidak boleh di masa depan.');
      return;
    }
    final repo = ref.read(glucoseRepositoryProvider);
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
        'originalValue': num.parse(value.text.trim().replaceAll(',', '.')),
        'originalUnit': unit,
        'measuredAt': time.toUtc().toIso8601String(),
        'mealContext': mealContext,
        'source': 'manual_glucometer',
        'measurementType': 'capillary_blood',
        'qualityStatus': review ? 'needs_review' : 'user_reported',
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
      }, id: widget.initial?.id);
      if (!mounted || !repo.isCurrentAccount()) return;
      if (widget.initial == null) {
        ref
            .read(usageTrackerProvider)
            .formSaved('glucose', DateTime.now().difference(opened));
        announce(context, 'Glukosa tersimpan');
      }
      ref.invalidate(todayProvider);
      ref.invalidate(glucoseProvider(saved.id));
      ref.invalidate(glucosePageProvider);
      ref.invalidate(glucoseDayProvider);
      setState(() {
        dirty = false;
        uncertain = false;
      });
      context.go('${Routes.glucose}/${saved.id}');
    } on QueuedOffline {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(queuedOfflineMessage)));
        setState(() => dirty = false);
        context.go(Routes.glucose);
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
    return DiscardGuard(
      dirty: dirty,
      child: PageScaffold(
        title: widget.initial == null ? 'Catat glukosa' : 'Koreksi glukosa',
        bottom: SaveBar(
          button: PillButton(
            label: widget.initial == null ? 'Simpan glukosa' : 'Simpan koreksi',
            loading: busy,
            onPressed: conflict ? null : save,
          ),
          note: widget.initial == null
              ? 'Tanpa koneksi, catatan disimpan di perangkat dan dikirim nanti.'
              : 'Koreksi perlu koneksi.',
        ),
        children: [
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FormHero.domain(
                  DomainStyle.glucose,
                  'Glukometer darah kapiler',
                  subtitle:
                      'Dilaporkan sendiri · angka tidak dikonversi otomatis',
                ),
                FormSection(
                  title: 'Nilai',
                  children: [
                    AppTextField(
                      label: 'Nilai pengukuran',
                      hint: 'mis. 110',
                      controller: value,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      enabled: !locked,
                      validator: (v) => validateGlucoseInput(v, unit),
                      onChanged: (_) => setState(() => dirty = true),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final u in ['mg/dL', 'mmol/L'])
                          PillChip(
                            label: u,
                            selected: unit == u,
                            onTap: locked
                                ? null
                                : () => setState(() {
                                    unit = u;
                                    dirty = true;
                                  }),
                          ),
                      ],
                    ),
                    const FormNote(
                      'Pilih satuan yang tertera di alat. Angka tidak dikonversi otomatis.',
                    ),
                    if (glucoseAlertFor(
                          num.tryParse(value.text.trim().replaceAll(',', '.')),
                          unit,
                        )
                        case final alert?)
                      GlucoseAlertCard(alert: alert),
                  ],
                ),
                FormSection(
                  title: 'Waktu & konteks',
                  children: [
                    DateTimeTile(
                      label: 'Waktu pengukuran',
                      value: time,
                      detail: time.timeZoneName,
                      onTap: locked ? null : pickTime,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Konteks pengukuran',
                      style: AppTypography.secondaryStrong,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final entry in glucoseContexts.entries)
                          PillChip(
                            label: entry.value,
                            selected: mealContext == entry.key,
                            onTap: locked
                                ? null
                                : () => setState(() {
                                    mealContext = entry.key;
                                    dirty = true;
                                  }),
                          ),
                      ],
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tandai untuk ditinjau'),
                      subtitle: const Text(
                        'Tetap disimpan; tidak disertakan dalam rata-rata.',
                      ),
                      value: review,
                      onChanged: locked
                          ? null
                          : (v) => setState(() {
                              review = v!;
                              dirty = true;
                            }),
                    ),
                  ],
                ),
                FormSection(
                  title: widget.initial == null
                      ? 'Catatan'
                      : 'Catatan & alasan',
                  children: [
                    AppTextField(
                      label: 'Catatan (opsional)',
                      hint: 'mis. sebelum sarapan',
                      controller: notes,
                      maxLength: 2000,
                      enabled: !locked,
                      onChanged: (_) => setState(() => dirty = true),
                    ),
                    if (widget.initial != null) ...[
                      const SizedBox(height: 8),
                      AppTextField(
                        label: 'Alasan koreksi',
                        hint: 'mis. salah ketik angka',
                        controller: reason,
                        maxLength: 300,
                        enabled: !locked,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Isi alasan koreksi.'
                            : null,
                        onChanged: (_) => setState(() => dirty = true),
                      ),
                    ],
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
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
                      ref.invalidate(glucoseProvider(id));
                      context.go(
                        conflict ? '${Routes.glucose}/$id' : Routes.glucose,
                      );
                    },
                    child: Text(
                      conflict ? 'Muat ulang catatan' : 'Periksa riwayat',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
