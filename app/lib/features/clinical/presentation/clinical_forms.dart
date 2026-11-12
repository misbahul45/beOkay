import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/usage_tracker.dart';
import '../../../core/ids/record_id.dart';
import '../../../core/network/account_scoped_repository.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/discard_guard.dart';
import '../../../core/widgets/domain_style.dart';
import '../../../core/widgets/form_kit.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/clinical_controller.dart';
import '../data/clinical_models.dart';

num? parseNum(String text) => num.tryParse(text.trim().replaceAll(',', '.'));

class VitalFormScreen extends ConsumerStatefulWidget {
  const VitalFormScreen({super.key, this.kind, this.initial});
  final String? kind;
  final VitalRecord? initial;
  @override
  ConsumerState<VitalFormScreen> createState() => _VitalFormScreenState();
}

class _VitalFormScreenState extends ConsumerState<VitalFormScreen> {
  final form = GlobalKey<FormState>();
  final recordId = newRecordId();
  final opened = DateTime.now();
  late String kind =
      widget.initial?.kind ??
      (vitalKinds.containsKey(widget.kind) ? widget.kind! : 'weight');
  late final value = TextEditingController(
    text: widget.initial == null ? '' : fmtNum(widget.initial!.value),
  );
  late final value2 = TextEditingController(
    text: widget.initial?.value2 == null ? '' : fmtNum(widget.initial!.value2!),
  );
  late final notes = TextEditingController(text: widget.initial?.notes);
  final reason = TextEditingController();
  late DateTime time = widget.initial?.measuredAt.toLocal() ?? DateTime.now();
  bool busy = false, dirty = false;
  String? error;

  bool get bp => kind == 'blood_pressure';
  String get unit => vitalKinds[kind]!.$2;

  @override
  void dispose() {
    value.dispose();
    value2.dispose();
    notes.dispose();
    reason.dispose();
    super.dispose();
  }

  String? _range(String? text, num min, num max) {
    final v = parseNum(text ?? '');
    if (v == null || v < min || v > max) return 'Masukkan angka $min–$max.';
    return null;
  }

  Future<void> pickTime() async {
    final day = await showDatePicker(
      context: context,
      initialDate: time,
      firstDate: DateTime(1990),
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
    final repo = ref.read(clinicalRepositoryProvider);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final body = {
        if (widget.initial == null) ...{'id': recordId, 'kind': kind},
        if (widget.initial != null) ...{
          'expectedVersion': widget.initial!.version,
          'reason': reason.text.trim(),
        },
        'value': parseNum(value.text),
        if (bp) 'value2': parseNum(value2.text),
        'unit': unit,
        'measuredAt': time.toUtc().toIso8601String(),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
      };
      await repo.saveVital(body, id: widget.initial?.id);
      ref
          .read(usageTrackerProvider)
          .formSaved('vital', DateTime.now().difference(opened));
      _done();
    } on QueuedOffline {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(queuedOfflineMessage)));
        _done();
      }
    } catch (e) {
      if (mounted) setState(() => error = messageFor(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _done() {
    if (!mounted) return;
    ref.invalidate(clinicalSummaryProvider);
    ref.invalidate(vitalHistoryProvider(kind));
    setState(() => dirty = false);
    context.canPop() ? context.pop() : context.go(Routes.clinical);
  }

  @override
  Widget build(BuildContext context) => DiscardGuard(
    dirty: dirty,
    child: PageScaffold(
      title: widget.initial == null
          ? 'Catat ukuran tubuh'
          : 'Koreksi ${vitalKinds[kind]!.$1.toLowerCase()}',
      bottom: SaveBar(
        button: PillButton(
          label: widget.initial == null ? 'Simpan' : 'Simpan koreksi',
          loading: busy,
          onPressed: save,
        ),
        note: widget.initial == null
            ? 'Tanpa koneksi, catatan disimpan di perangkat dan dikirim nanti.'
            : null,
      ),
      children: [
        Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FormHero.domain(
                DomainStyle.clinical,
                vitalKinds[kind]!.$1,
                subtitle: 'Dilaporkan sendiri · tanpa penilaian klinis',
              ),
              if (widget.initial == null)
                FormSection(
                  title: 'Jenis',
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final e in vitalKinds.entries)
                          PillChip(
                            label: e.value.$1,
                            selected: kind == e.key,
                            onTap: busy
                                ? null
                                : () => setState(() {
                                    kind = e.key;
                                    dirty = true;
                                  }),
                          ),
                      ],
                    ),
                  ],
                ),
              FormSection(
                title: 'Nilai',
                children: [
                  AppTextField(
                    label: bp
                        ? 'Sistolik (angka atas)'
                        : '${vitalKinds[kind]!.$1} ($unit)',
                    hint: bp
                        ? 'mis. 128'
                        : kind == 'weight'
                        ? 'mis. 68,5'
                        : 'mis. 160',
                    controller: value,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) => switch (kind) {
                      'weight' => _range(v, 10, 500),
                      'height' => _range(v, 50, 250),
                      'waist' => _range(v, 30, 300),
                      _ => _range(v, 40, 300),
                    },
                    onChanged: (_) => setState(() => dirty = true),
                  ),
                  if (bp) ...[
                    const SizedBox(height: 8),
                    AppTextField(
                      label: 'Diastolik (angka bawah)',
                      hint: 'mis. 82',
                      controller: value2,
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final r = _range(v, 20, 200);
                        if (r != null) return r;
                        final s = parseNum(value.text);
                        return s != null && parseNum(v ?? '')! >= s
                            ? 'Angka bawah harus lebih kecil dari angka atas.'
                            : null;
                      },
                      onChanged: (_) => setState(() => dirty = true),
                    ),
                    const FormNote(
                      'Tulis apa adanya dari alat tensimeter, dalam mmHg.',
                    ),
                  ],
                ],
              ),
              FormSection(
                title: 'Waktu',
                children: [
                  DateTimeTile(
                    label: 'Waktu pengukuran',
                    value: time,
                    onTap: busy ? null : pickTime,
                  ),
                ],
              ),
              FormSection(
                title: widget.initial == null ? 'Catatan' : 'Catatan & alasan',
                children: [
                  AppTextField(
                    label: 'Catatan (opsional)',
                    controller: notes,
                    maxLength: 2000,
                    onChanged: (_) => setState(() => dirty = true),
                  ),
                  if (widget.initial != null) ...[
                    const SizedBox(height: 8),
                    AppTextField(
                      label: 'Alasan koreksi',
                      controller: reason,
                      maxLength: 300,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Isi alasan koreksi.'
                          : null,
                    ),
                  ],
                ],
              ),
              if (error != null) ErrorBanner(error!),
            ],
          ),
        ),
      ],
    ),
  );
}

class LabFormScreen extends ConsumerStatefulWidget {
  const LabFormScreen({super.key, this.test, this.initial});
  final String? test;
  final LabRecord? initial;
  @override
  ConsumerState<LabFormScreen> createState() => _LabFormScreenState();
}

class _LabFormScreenState extends ConsumerState<LabFormScreen> {
  final form = GlobalKey<FormState>();
  final recordId = newRecordId();
  final opened = DateTime.now();
  late String test =
      widget.initial?.test ??
      (labTests.containsKey(widget.test) ? widget.test! : 'hba1c');
  late String unit = widget.initial?.unit ?? labTests[test]!.$2.first;
  late final value = TextEditingController(
    text: widget.initial == null ? '' : fmtNum(widget.initial!.value),
  );
  late final labName = TextEditingController(text: widget.initial?.labName);
  late final notes = TextEditingController(text: widget.initial?.notes);
  final reason = TextEditingController();
  late DateTime sampled = widget.initial == null
      ? DateTime.now()
      : DateTime.parse(widget.initial!.sampledAt);
  late bool fromReport = widget.initial?.source != 'manual';
  bool busy = false, dirty = false;
  String? error;

  @override
  void dispose() {
    value.dispose();
    labName.dispose();
    notes.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> pickDate() async {
    final day = await showDatePicker(
      context: context,
      initialDate: sampled,
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
    );
    if (day != null && mounted) {
      setState(() {
        sampled = day;
        dirty = true;
      });
    }
  }

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    final repo = ref.read(clinicalRepositoryProvider);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await repo.saveLab({
        if (widget.initial == null) ...{'id': recordId, 'test': test},
        if (widget.initial != null) ...{
          'expectedVersion': widget.initial!.version,
          'reason': reason.text.trim(),
        },
        'value': parseNum(value.text),
        'unit': unit,
        'sampledAt': _date(sampled),
        'labName': labName.text.trim().isEmpty ? null : labName.text.trim(),
        'source': fromReport ? 'lab_report' : 'manual',
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
      }, id: widget.initial?.id);
      ref
          .read(usageTrackerProvider)
          .formSaved('lab', DateTime.now().difference(opened));
      _done();
    } on QueuedOffline {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(queuedOfflineMessage)));
        _done();
      }
    } catch (e) {
      if (mounted) setState(() => error = messageFor(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _done() {
    if (!mounted) return;
    ref.invalidate(clinicalSummaryProvider);
    ref.invalidate(labHistoryProvider(test));
    setState(() => dirty = false);
    context.canPop() ? context.pop() : context.go(Routes.clinical);
  }

  @override
  Widget build(BuildContext context) => DiscardGuard(
    dirty: dirty,
    child: PageScaffold(
      title: widget.initial == null
          ? 'Catat hasil lab'
          : 'Koreksi ${labTests[test]!.$1}',
      bottom: SaveBar(
        button: PillButton(
          label: widget.initial == null ? 'Simpan hasil' : 'Simpan koreksi',
          loading: busy,
          onPressed: save,
        ),
        note: widget.initial == null
            ? 'Tanpa koneksi, catatan disimpan di perangkat dan dikirim nanti.'
            : null,
      ),
      children: [
        Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FormHero.domain(
                DomainStyle.clinical,
                labTests[test]!.$1,
                subtitle:
                    'Salin dari lembar hasil lab · tanpa penilaian klinis',
              ),
              if (widget.initial == null)
                FormSection(
                  title: 'Jenis pemeriksaan',
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final e in labTests.entries)
                          PillChip(
                            label: e.value.$1,
                            selected: test == e.key,
                            onTap: busy
                                ? null
                                : () => setState(() {
                                    test = e.key;
                                    unit = e.value.$2.first;
                                    dirty = true;
                                  }),
                          ),
                      ],
                    ),
                  ],
                ),
              FormSection(
                title: 'Hasil',
                children: [
                  AppTextField(
                    label: 'Nilai',
                    hint: test == 'hba1c' ? 'mis. 7,2' : null,
                    controller: value,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) {
                      final n = parseNum(v ?? '');
                      return n == null || n <= 0
                          ? 'Masukkan angka seperti di lembar hasil.'
                          : null;
                    },
                    onChanged: (_) => setState(() => dirty = true),
                  ),
                  const SizedBox(height: 8),
                  Text('Satuan', style: AppTypography.secondaryStrong),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final u in labTests[test]!.$2)
                        PillChip(
                          label: u,
                          selected: unit == u,
                          onTap: busy
                              ? null
                              : () => setState(() {
                                  unit = u;
                                  dirty = true;
                                }),
                        ),
                    ],
                  ),
                  const FormNote(
                    'Pilih satuan yang tertulis di lembar hasil. Angka tidak dikonversi.',
                  ),
                ],
              ),
              FormSection(
                title: 'Pemeriksaan',
                children: [
                  DateTimeTile(
                    label: 'Tanggal pengambilan sampel',
                    value: sampled,
                    showTime: false,
                    onTap: busy ? null : pickDate,
                  ),
                  const SizedBox(height: 8),
                  AppTextField(
                    label: 'Nama laboratorium (opsional)',
                    controller: labName,
                    maxLength: 120,
                    onChanged: (_) => setState(() => dirty = true),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Disalin dari lembar hasil lab'),
                    subtitle: const Text(
                      'Matikan bila angka berasal dari ingatan atau pesan.',
                    ),
                    value: fromReport,
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            fromReport = v!;
                            dirty = true;
                          }),
                  ),
                ],
              ),
              FormSection(
                title: widget.initial == null ? 'Catatan' : 'Catatan & alasan',
                children: [
                  AppTextField(
                    label: 'Catatan (opsional)',
                    controller: notes,
                    maxLength: 2000,
                    onChanged: (_) => setState(() => dirty = true),
                  ),
                  if (widget.initial != null) ...[
                    const SizedBox(height: 8),
                    AppTextField(
                      label: 'Alasan koreksi',
                      controller: reason,
                      maxLength: 300,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Isi alasan koreksi.'
                          : null,
                    ),
                  ],
                ],
              ),
              if (error != null) ErrorBanner(error!),
              const SizedBox(height: 8),
              const InfoCard(
                tone: InfoTone.neutral,
                text:
                    'beOkay tidak menilai hasil lab. Tanyakan artinya kepada dokter atau tenaga kesehatanmu.',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
