import '../../../core/voice/voice_input.dart';
import '../../../core/a11y/announce.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/account_scoped_repository.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/network/api_exception.dart';
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
import '../../today/application/today_controller.dart';
import '../application/nutrition_controller.dart';
import '../data/nutrition_models.dart';
import '../../../core/analytics/usage_tracker.dart';
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
  final opened = DateTime.now();
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
        repository: repo,
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
      if (widget.initial == null) {
        ref
            .read(usageTrackerProvider)
            .formSaved('meal', DateTime.now().difference(opened));
        announce(context, 'Catatan makan tersimpan');
      }
      ref.invalidate(todayProvider);
      ref.invalidate(mealProvider(saved.id));
      setState(() {
        dirty = false;
        uncertain = false;
      });
      context.go('${Routes.meals}/${saved.id}');
    } on QueuedOffline {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(queuedOfflineMessage)));
        setState(() => dirty = false);
        context.go(Routes.meals);
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
    final locked = busy || uncertain;
    return DiscardGuard(
      dirty: dirty,
      child: PageScaffold(
        title: widget.initial == null ? 'Catat makanan' : 'Koreksi catatan',
        bottom: SaveBar(
          button: PillButton(
            label: widget.initial == null ? 'Simpan makanan' : 'Simpan koreksi',
            loading: busy,
            onPressed: conflict ? null : save,
          ),
          note: items.isEmpty
              ? 'Tambahkan minimal satu makanan.'
              : '${items.length} makanan · gizi hanya dari item yang beratnya diketahui',
        ),
        children: [
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FormHero.domain(
                  DomainStyle.meal,
                  'Apa yang kamu makan?',
                  subtitle:
                      'Nilai gizi hanya dihitung dari porsi yang diketahui; tidak ada angka yang ditebak.',
                ),
                FormSection(
                  title: 'Waktu makan',
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final entry in mealCategories.entries)
                          PillChip(
                            label: entry.value,
                            selected: category == entry.key,
                            onTap: locked
                                ? null
                                : () => setState(() {
                                    category = entry.key;
                                    dirty = true;
                                  }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DateTimeTile(
                      label: 'Waktu',
                      value: time,
                      detail: time.timeZoneName,
                      onTap: locked ? null : pickTime,
                    ),
                  ],
                ),
                FormSection(
                  title: 'Makanan',
                  subtitle: items.isEmpty
                      ? 'Cari dari referensi atau tambah item tanpa nilai gizi.'
                      : null,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
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
                                    onPressed: locked
                                        ? null
                                        : () => addItem(index: i),
                                    child: const Text('Ubah porsi'),
                                  ),
                                  TextButton(
                                    onPressed: locked
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
                    if (items.length < 30)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          PillButton(
                            label: 'Cari makanan',
                            icon: Icons.search_rounded,
                            kind: PillButtonKind.secondary,
                            expand: false,
                            onPressed: locked
                                ? null
                                : () => addItem(catalog: true),
                          ),
                          PillButton(
                            label: 'Tambah item tanpa nilai gizi',
                            kind: PillButtonKind.ghost,
                            expand: false,
                            onPressed: locked ? null : () => addItem(),
                          ),
                        ],
                      ),
                  ],
                ),
                FormSection(
                  title: 'Ringkasan gizi',
                  children: [NutritionTotals(totals: totals)],
                ),
                FormSection(
                  title: widget.initial == null
                      ? 'Catatan'
                      : 'Catatan & alasan',
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: AppTextField(
                            label: 'Catatan (opsional)',
                            hint: 'mis. makan di kantor',
                            controller: notes,
                            maxLength: 2000,
                            enabled: !locked,
                            onChanged: (_) => setState(() => dirty = true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: MicButton(
                            controller: notes,
                            domain: 'meal',
                            enabled: !locked,
                            onChanged: () => setState(() => dirty = true),
                          ),
                        ),
                      ],
                    ),
                    if (widget.initial != null) ...[
                      const SizedBox(height: 8),
                      AppTextField(
                        label: 'Alasan koreksi',
                        hint: 'mis. porsi salah',
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
