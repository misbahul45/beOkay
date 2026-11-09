import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/ids/record_id.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/discard_guard.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../preferences/application/preferences_controller.dart';
import '../application/medication_controller.dart';
import '../data/medication_repository.dart';

class MedicationFormScreen extends ConsumerStatefulWidget {
  const MedicationFormScreen({super.key, this.initial});
  final Regimen? initial;
  @override
  ConsumerState<MedicationFormScreen> createState() => _State();
}

class _State extends ConsumerState<MedicationFormScreen> {
  final _form = GlobalKey<FormState>();
  final name = TextEditingController(), strength = TextEditingController(), dosageForm = TextEditingController(), instructions = TextEditingController();
  final reason = TextEditingController();
  bool get editing => widget.initial != null;
  TimeOfDay? time;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    if (r != null) {
      name.text = r.name;
      strength.text = r.strength ?? '';
      dosageForm.text = r.dosageForm ?? '';
      instructions.text = r.instructions ?? '';
    }
  }
  final days = <int>{1, 2, 3, 4, 5, 6, 7};
  bool saving = false, dirty = false;
  String? error;
  // Stable ids make a retry after a lost response idempotent.
  final regimenId = newRecordId(), scheduleId = newRecordId();
  static const dayNames = {1: 'Sen', 2: 'Sel', 3: 'Rab', 4: 'Kam', 5: 'Jum', 6: 'Sab', 7: 'Min'};

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (saving || !_form.currentState!.validate()) return;
    setState(() { saving = true; error = null; });
    final repo = ref.read(medicationRepositoryProvider);
    try {
      final r = widget.initial;
      if (r != null) {
        await repo.updateRegimen(r.id, {
          if (name.text.trim() != r.name) 'name': name.text.trim(),
          if (_opt(strength) != r.strength) 'strength': _opt(strength),
          if (_opt(dosageForm) != r.dosageForm) 'dosageForm': _opt(dosageForm),
          if (_opt(instructions) != r.instructions) 'dosingInstructions': _opt(instructions),
          'expectedVersion': r.version,
          'reason': reason.text.trim(),
        });
        ref.invalidate(medicationListProvider);
        ref.invalidate(medicationTodayProvider);
        if (mounted) { dirty = false; context.pop(); }
        return;
      }
      await repo.createRegimen({'id': regimenId, 'name': name.text.trim(), 'strength': _opt(strength), 'dosageForm': _opt(dosageForm), 'dosingInstructions': _opt(instructions)});
      if (time != null) {
        final tz = ref.read(effectivePreferencesProvider).timezone;
        await repo.createSchedule(regimenId, {
          'id': scheduleId,
          'localTime': '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}',
          'timezone': tz,
          'daysOfWeek': (days.toList()..sort()),
          'effectiveFrom': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        });
      }
      ref.invalidate(medicationListProvider);
      ref.invalidate(medicationTodayProvider);
      if (mounted) { dirty = false; context.pop(); }
    } catch (e) {
      if (mounted) setState(() => error = messageFor(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DiscardGuard(
      dirty: dirty && !saving,
      child: PageScaffold(
        title: editing ? 'Ubah obat' : 'Tambah obat',
        bottom: PillButton(label: editing ? 'Simpan perubahan' : 'Simpan obat', loading: saving, onPressed: _save),
        children: [
          Form(
            key: _form,
            onChanged: () => dirty = true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Salin dari resep atau label yang kamu terima.', style: AppTypography.secondary),
                const SizedBox(height: AppSpacing.md),
                AppTextField(label: 'Nama obat', controller: name, hint: 'mis. Metformin', validator: (v) => (v ?? '').trim().isEmpty ? 'Nama obat wajib diisi.' : null),
                const SizedBox(height: AppSpacing.md),
                AppTextField(label: 'Kekuatan (opsional)', controller: strength, hint: 'mis. 500 mg'),
                const SizedBox(height: AppSpacing.md),
                AppTextField(label: 'Bentuk sediaan (opsional)', controller: dosageForm, hint: 'mis. tablet'),
                const SizedBox(height: AppSpacing.md),
                AppTextField(label: 'Instruksi dari resep (opsional)', controller: instructions, hint: 'mis. 1 tablet sesudah makan malam', helper: 'beOkay tidak memberi atau mengubah dosis.'),
                const SizedBox(height: AppSpacing.lg),
                if (editing) ...[
                  AppTextField(label: 'Alasan perubahan', controller: reason, hint: 'mis. Dosis diganti dokter', maxLength: 300, validator: (v) => (v ?? '').trim().isEmpty ? 'Isi alasan perubahan.' : null),
                  const InfoCard(tone: InfoTone.neutral, text: 'Riwayat konfirmasi lama tidak berubah: setiap konfirmasi menyimpan nama dan kekuatan saat itu.'),
                ] else ...[
                Text('Jadwal pengingat (opsional)', style: AppTypography.title),
                const SizedBox(height: AppSpacing.xs),
                PillButton(
                  label: time == null ? 'Pilih jam' : time!.format(context),
                  icon: Icons.schedule_rounded,
                  kind: PillButtonKind.secondary,
                  expand: false,
                  onPressed: () async {
                    final picked = await showTimePicker(context: context, initialTime: time ?? const TimeOfDay(hour: 8, minute: 0));
                    if (picked != null) setState(() { time = picked; dirty = true; });
                  },
                ),
                if (time != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      for (final d in dayNames.entries)
                        PillChip(label: d.value, selected: days.contains(d.key), onTap: () => setState(() { if (days.contains(d.key)) { if (days.length > 1) days.remove(d.key); } else { days.add(d.key); } dirty = true; })),
                    ],
                  ),
                ],
                ],
                if (error != null) ...[const SizedBox(height: AppSpacing.md), ErrorBanner(error!)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
