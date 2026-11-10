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
import '../application/goals_controller.dart';
import '../data/goals_repository.dart';

class GoalFormScreen extends ConsumerStatefulWidget {
  const GoalFormScreen({super.key, this.initial});
  final Goal? initial;
  @override
  ConsumerState<GoalFormScreen> createState() => _State();
}

class _State extends ConsumerState<GoalFormScreen> {
  final _form = GlobalKey<FormState>();
  final title = TextEditingController(), target = TextEditingController();
  String type = 'manual_checkins', period = 'weekly';
  bool saving = false, dirty = false;
  String? error;
  final id = newRecordId();
  final reason = TextEditingController();
  bool get editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final g = widget.initial;
    if (g != null) {
      title.text = g.title;
      target.text = g.target == g.target.roundToDouble()
          ? g.target.toInt().toString()
          : g.target.toString();
      type = g.type;
      period = g.period;
    }
  }

  static const targetHints = {
    'manual_checkins': 'mis. 3',
    'activity_minutes': 'mis. 150',
    'walking_sessions': 'mis. 3',
    'record_meals': 'mis. 5',
    'record_glucose': 'mis. 3',
  };
  static const targetUnits = {
    'manual_checkins': 'kali check-in',
    'activity_minutes': 'menit',
    'walking_sessions': 'sesi',
    'record_meals': 'hari mencatat',
    'record_glucose': 'hari mencatat',
  };

  Future<void> _save() async {
    if (saving || !_form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final tv = num.parse(target.text.trim().replaceAll(',', '.'));
      final g = widget.initial;
      if (g != null) {
        await ref.read(goalsRepositoryProvider).update(g.id, {
          if (title.text.trim() != g.title) 'title': title.text.trim(),
          if (tv != g.target) 'targetValue': tv,
          'expectedVersion': g.version,
          'reason': reason.text.trim(),
        });
        ref.invalidate(goalsListProvider);
        if (mounted) {
          dirty = false;
          context.pop();
        }
        return;
      }
      await ref.read(goalsRepositoryProvider).create({
        'id': id,
        'title': title.text.trim(),
        'goalType': type,
        'targetValue': num.parse(target.text.trim().replaceAll(',', '.')),
        'period': period,
        'startDate': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'endDate': null,
      });
      ref.invalidate(goalsListProvider);
      if (mounted) {
        dirty = false;
        context.pop();
      }
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
        title: editing ? 'Ubah tujuan' : 'Buat tujuan',
        bottom: PillButton(
          label: editing ? 'Simpan perubahan' : 'Simpan tujuan',
          loading: saving,
          onPressed: _save,
        ),
        children: [
          Form(
            key: _form,
            onChanged: () => dirty = true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: 'Nama tujuan',
                  controller: title,
                  hint: 'mis. Jalan kaki sore',
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'Nama tujuan wajib diisi.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Jenis tujuan', style: AppTypography.secondaryStrong),
                const SizedBox(height: AppSpacing.xs),
                if (editing)
                  Text(goalTypes[type]!, style: AppTypography.body)
                else
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      for (final e in goalTypes.entries)
                        PillChip(
                          label: e.value,
                          selected: type == e.key,
                          onTap: () => setState(() {
                            type = e.key;
                            dirty = true;
                          }),
                        ),
                    ],
                  ),
                const SizedBox(height: 4),
                Text(goalTypeHints[type]!, style: AppTypography.caption),
                const SizedBox(height: AppSpacing.md),
                if (!editing) ...[
                  Text('Periode', style: AppTypography.secondaryStrong),
                  const SizedBox(height: AppSpacing.xs),
                  SegmentedPills<String>(
                    options: const [
                      ('weekly', 'Mingguan'),
                      ('daily', 'Harian'),
                    ],
                    value: period,
                    onChanged: (v) => setState(() {
                      period = v;
                      dirty = true;
                    }),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                AppTextField(
                  label: 'Target (${targetUnits[type]})',
                  controller: target,
                  hint: targetHints[type],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    final n = num.tryParse(
                      (v ?? '').trim().replaceAll(',', '.'),
                    );
                    return n == null || n <= 0
                        ? 'Isi angka lebih dari 0.'
                        : null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                if (editing) ...[
                  AppTextField(
                    label: 'Alasan perubahan',
                    controller: reason,
                    hint: 'mis. Target disesuaikan',
                    maxLength: 300,
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Isi alasan perubahan.'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                if (error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  ErrorBanner(error!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
