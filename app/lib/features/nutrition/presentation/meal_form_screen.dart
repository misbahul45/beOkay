import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/discard_guard.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../today/application/today_controller.dart';
import '../application/nutrition_controller.dart';
import '../data/nutrition_models.dart';
import 'food_picker.dart';
import 'meal_item_editor.dart';
import 'nutrition_widgets.dart';

class MealFormScreen extends ConsumerStatefulWidget {
  const MealFormScreen({super.key, this.initial});
  final MealRecord? initial;
  @override
  ConsumerState<MealFormScreen> createState() => _MealFormScreenState();
}

class _MealFormScreenState extends ConsumerState<MealFormScreen> {
  final form = GlobalKey<FormState>();
  final recordId = newRecordId();
  late final notes = TextEditingController(text: widget.initial?.notes);
  final reason = TextEditingController();
  late String category = widget.initial?.category ?? 'lunch';
  late DateTime time = widget.initial?.consumedAt.toLocal() ?? DateTime.now();
  late List<MealItemDraft> items = [...?widget.initial?.items];
  bool busy = false, dirty = false;
  String? error;
  bool uncertain = false;
  bool conflict = false;
  @override
  void dispose() {
    notes.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> pickTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: time,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final clock = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(time),
    );
    if (clock != null && mounted) {
      setState(() {
        time = DateTime(
          date.year,
          date.month,
          date.day,
          clock.hour,
          clock.minute,
        );
        dirty = true;
      });
    }
  }

  Future<void> addItem({bool catalog = false, int? index}) async {
    final repo = ref.read(nutritionRepositoryProvider);
    final food = catalog ? await pickFood(context, repo) : null;
    if (!mounted || (catalog && food == null)) return;
    final item = await showDialog<MealItemDraft>(
      context: context,
      builder: (_) => MealItemEditor(
        initial: index == null ? null : items[index],
        food: food,
      ),
    );
    if (item != null && mounted) {
      setState(() {
        if (index == null) {
          items.add(item);
        } else {
          items[index] = item;
        }
        dirty = true;
      });
    }
  }

  Future<void> save() async {
    if (items.isEmpty) {
      setState(() => error = 'Tambahkan setidaknya satu makanan.');
      return;
    }
    if (!form.currentState!.validate()) return;
    if (time.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      setState(() => error = 'Waktu makan tidak boleh di masa depan.');
      return;
    }
    final repo = ref.read(nutritionRepositoryProvider);
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
        'category': category,
        'consumedAt': time.toUtc().toIso8601String(),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'items': items.map((item) => item.toInput()).toList(),
      }, id: widget.initial?.id);
      if (!mounted || !repo.isCurrentAccount()) return;
      ref.invalidate(todayProvider);
      ref.invalidate(mealProvider(saved.id));
      setState(() {
        dirty = false;
        uncertain = false;
      });
      context.go('${Routes.meals}/${saved.id}');
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
    final totals = {
      for (final key in nutrientLabels.keys)
        key: () {
          final known = items
              .map((item) => item.nutrient(key))
              .whereType<num>()
              .toList();
          return NutrientTotal(
            known.isEmpty ? null : known.fold<num>(0, (a, b) => a + b),
            known.isEmpty
                ? 'UNKNOWN'
                : known.length == items.length
                ? 'COMPLETE'
                : 'PARTIAL',
            known.length,
            items.length,
          );
        }(),
    };
    return DiscardGuard(
      dirty: dirty,
      child: PageScaffold(
        title: widget.initial == null ? 'Catat makanan' : 'Koreksi catatan',
        children: [
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.initial == null
                      ? 'Apa yang kamu makan?'
                      : 'Perbarui catatanmu.',
                  style: AppTypography.headline,
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in mealCategories.entries)
                      PillChip(
                        label: entry.value,
                        selected: category == entry.key,
                        onTap: busy || uncertain
                            ? null
                            : () => setState(() {
                                category = entry.key;
                                dirty = true;
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                PillButton(
                  label:
                      'Waktu makan: ${DateFormat('d MMM y, HH:mm', 'id_ID').format(time)}',
                  kind: PillButtonKind.secondary,
                  onPressed: busy || uncertain ? null : pickTime,
                ),
                const SizedBox(height: 8),
                Text(
                  'Waktu dipilih dalam zona perangkat (${time.timeZoneName}). Histori ditampilkan dalam zona waktu preferensimu.',
                  style: AppTypography.secondary,
                ),
                const SizedBox(height: 24),
                for (var i = 0; i < items.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: NutritionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(items[i].name, style: AppTypography.title),
                          Text(
                            '${items[i].quantity} ${portionUnits[items[i].unit] ?? items[i].unit}',
                            style: AppTypography.body,
                          ),
                          Wrap(
                            children: [
                              TextButton(
                                onPressed: busy || uncertain
                                    ? null
                                    : () => addItem(index: i),
                                child: const Text('Ubah porsi'),
                              ),
                              TextButton(
                                onPressed: busy || uncertain
                                    ? null
                                    : () => setState(() {
                                        items.removeAt(i);
                                        dirty = true;
                                      }),
                                child: const Text('Hapus item'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                if (items.length < 30) ...[
                  PillButton(
                    label: 'Cari di katalog',
                    kind: PillButtonKind.secondary,
                    onPressed: busy || uncertain
                        ? null
                        : () => addItem(catalog: true),
                  ),
                  const SizedBox(height: 12),
                  PillButton(
                    label: 'Tambah item tanpa nilai gizi',
                    kind: PillButtonKind.secondary,
                    onPressed: busy || uncertain ? null : () => addItem(),
                  ),
                ],
                const SizedBox(height: 24),
                NutritionTotals(totals: totals),
                const SizedBox(height: 24),
                AppTextField(
                  label: 'Catatan (opsional)',
                  controller: notes,
                  maxLength: 2000,
                  enabled: !busy && !uncertain,
                  onChanged: (_) => setState(() => dirty = true),
                ),
                if (widget.initial != null) ...[
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Alasan koreksi',
                    controller: reason,
                    maxLength: 300,
                    enabled: !busy && !uncertain,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Isi alasan koreksi.'
                        : null,
                    onChanged: (_) => setState(() => dirty = true),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 16),
                  ErrorBanner(error!),
                ],
                if (uncertain) ...[
                  const SizedBox(height: 12),
                  if (conflict)
                    const Text(
                      'Catatan berubah. Muat ulang untuk meninjau versi terbaru sebelum mengoreksi.',
                    )
                  else
                    const Text(
                      'Isi formulir dipertahankan. Periksa histori bila status simpan belum pasti; jangan membuat catatan baru yang sama.',
                    ),
                  TextButton(
                    onPressed: () {
                      final id = widget.initial?.id ?? recordId;
                      if (conflict) {
                        ref.invalidate(mealProvider(id));
                        context.go('${Routes.meals}/$id');
                      } else {
                        context.go(Routes.meals);
                      }
                    },
                    child: Text(
                      conflict ? 'Muat ulang catatan' : 'Periksa histori',
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                PillButton(
                  label: widget.initial == null
                      ? 'Simpan makanan'
                      : 'Simpan koreksi',
                  loading: busy,
                  onPressed: conflict ? null : save,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
