import 'package:flutter/material.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../data/nutrition_models.dart';
import '../data/nutrition_repository.dart';

String _fmt(num n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toString();

class MealItemEditor extends StatefulWidget {
  const MealItemEditor({super.key, this.initial, this.food, this.repository});
  final MealItemDraft? initial;
  final FoodReference? food;

  /// Bila ada dan makanan punya id, ukuran rumah tangga milik pengguna dapat dipakai.
  final NutritionRepository? repository;
  @override
  State<MealItemEditor> createState() => _MealItemEditorState();
}

class _MealItemEditorState extends State<MealItemEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.initial?.name ?? widget.food?.name,
  );
  late final quantity = TextEditingController(
    text: widget.initial?.quantity.toString() ?? '1',
  );
  late final grams = TextEditingController(
    text: widget.initial?.unit != 'g'
        ? widget.initial?.grams?.toString()
        : null,
  );
  late String unit = widget.initial?.unit ?? 'portion';
  List<PortionMeasure> measures = [];
  PortionMeasure? selected;
  Object? measureError;
  String? get foodId => widget.initial?.foodId ?? widget.food?.id;

  @override
  void initState() {
    super.initState();
    final repo = widget.repository, id = foodId;
    if (repo != null && id != null) {
      repo
          .measures(id)
          .then((v) {
            if (mounted) setState(() => measures = v);
          })
          .catchError((_) {});
    }
  }

  /// Total gram = jumlah × gram per ukuran; hanya ditampilkan bila jumlah valid.
  num? get measureGrams {
    final m = selected,
        q = num.tryParse(quantity.text.trim().replaceAll(',', '.'));
    if (m == null || q == null || q <= 0) return null;
    return (q * m.grams * 10000).round() / 10000;
  }

  Future<void> addMeasure() async {
    final added = await showDialog<PortionMeasure>(
      context: context,
      builder: (_) =>
          _MeasureDialog(repository: widget.repository!, foodId: foodId!),
    );
    if (added != null && mounted) {
      setState(() {
        measures = [...measures.where((m) => m.id != added.id), added]
          ..sort((a, b) => a.label.compareTo(b.label));
        selected = added;
        unit = 'portion';
      });
    }
  }

  @override
  void dispose() {
    name.dispose();
    quantity.dispose();
    grams.dispose();
    super.dispose();
  }

  String? validate(String? v, {bool optional = false}) {
    if (optional && (v == null || v.trim().isEmpty)) return null;
    final n = num.tryParse((v ?? '').replaceAll(',', '.'));
    return n == null || !n.isFinite || n <= 0 || n > 10000
        ? 'Isi jumlah lebih dari 0, maksimal 10000.'
        : null;
  }

  void save() {
    if (!form.currentState!.validate()) return;
    final g = unit == 'g'
        ? null
        : (selected != null
              ? measureGrams
              : num.tryParse(grams.text.trim().replaceAll(',', '.')));
    Navigator.pop(
      context,
      MealItemDraft(
        id: widget.initial?.id,
        foodId: widget.initial?.foodId ?? widget.food?.id,
        name: name.text.trim(),
        quantity: num.parse(quantity.text.replaceAll(',', '.')),
        unit: unit,
        grams: g,
        gramsBasis: g == null ? null : (selected?.basis ?? 'user_estimate'),
        per100g: widget.initial?.per100g ?? widget.food?.per100g ?? {},
        source:
            widget.initial?.source ?? widget.food?.source ?? 'user_reported',
        status: widget.initial?.status ?? widget.food?.status ?? 'unknown',
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? 'Tambah item' : 'Ubah porsi'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              label: 'Nama item',
              hint: 'mis. nasi pecel',
              controller: name,
              enabled: widget.food == null && widget.initial?.foodId == null,
              maxLength: 120,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Isi nama item.' : null,
            ),
            const SizedBox(height: 12),
            AppTextField(
              label: unit == 'g' ? 'Jumlah gram' : 'Jumlah porsi',
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) => validate(v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: unit,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Unit porsi'),
              items: const [
                DropdownMenuItem(value: 'portion', child: Text('Porsi')),
                DropdownMenuItem(value: 'g', child: Text('Gram')),
                DropdownMenuItem(value: 'piece', child: Text('Buah / potong')),
                DropdownMenuItem(value: 'ml', child: Text('mL')),
              ],
              onChanged: (v) => setState(() => unit = v!),
            ),
            const SizedBox(height: 12),
            if (widget.repository != null && foodId != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Ukuran rumah tangga',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in measures)
                    PillChip(
                      label: '${m.label} · ${_fmt(m.grams)} g',
                      selected: selected?.id == m.id,
                      onTap: () => setState(() {
                        selected = selected?.id == m.id ? null : m;
                        if (selected != null) unit = 'portion';
                      }),
                    ),
                  PillChip(
                    label: 'Tambah ukuran',
                    selected: false,
                    onTap: addMeasure,
                  ),
                ],
              ),
              if (measureError != null) ErrorBanner(messageFor(measureError!)),
              if (selected != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    measureGrams == null
                        ? 'Isi jumlah untuk menghitung berat.'
                        : 'Sekitar ${_fmt(measureGrams!)} g (${selected!.basisLabel}). Berat per ukuran hanya berlaku untuk makanan ini.',
                  ),
                ),
              if (measures.isEmpty && selected == null)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Belum ada ukuran. Tambahkan sendiri; tidak ada tabel konversi umum.',
                  ),
                ),
              const SizedBox(height: 12),
            ],
            if (unit != 'g' && selected == null)
              AppTextField(
                label: 'Total gram perkiraan (opsional)',
                hint: 'mis. 250',
                controller: grams,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                helper:
                    'Perkiraan berat seluruh item, bukan per porsi. Tanpa gram, nilai gizi tidak dihitung.',
                validator: (v) => validate(v, optional: true),
              ),
            if (unit == 'g')
              const Text(
                'Jumlah gram yang kamu laporkan dipakai untuk menghitung nilai gizi bila referensinya tersedia.',
              ),
            if (widget.food == null && widget.initial?.foodId == null)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Item tanpa referensi gizi disimpan dengan nilai yang belum diketahui.',
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      TextButton(onPressed: save, child: const Text('Gunakan item')),
    ],
  );
}

/// Dialog tambah ukuran rumah tangga. Mengelola controller-nya sendiri agar aman saat animasi tutup berjalan.
class _MeasureDialog extends StatefulWidget {
  const _MeasureDialog({required this.repository, required this.foodId});
  final NutritionRepository repository;
  final String foodId;
  @override
  State<_MeasureDialog> createState() => _MeasureDialogState();
}

class _MeasureDialogState extends State<_MeasureDialog> {
  final label = TextEditingController(), grams = TextEditingController();
  String basis = 'user_estimate';
  bool busy = false;
  Object? error;

  @override
  void dispose() {
    label.dispose();
    grams.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final g = num.tryParse(grams.text.trim().replaceAll(',', '.'));
    if (label.text.trim().isEmpty || g == null || g <= 0) {
      setState(() => error = 'Isi nama ukuran dan berat lebih dari 0 gram.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final m = await widget.repository.addMeasure(
        widget.foodId,
        label: label.text.trim(),
        grams: g,
        basis: basis,
      );
      if (mounted) Navigator.pop(context, m);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ukuran rumah tangga'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(
            label: 'Nama ukuran',
            hint: 'mis. 1 centong',
            controller: label,
            maxLength: 60,
          ),
          const SizedBox(height: 8),
          AppTextField(
            label: 'Berat satu ukuran (gram)',
            hint: 'mis. 100',
            controller: grams,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sudah ditimbang'),
            subtitle: const Text('Matikan bila hanya perkiraan'),
            value: basis == 'weighed',
            onChanged: busy
                ? null
                : (v) =>
                      setState(() => basis = v ? 'weighed' : 'user_estimate'),
          ),
          if (error != null)
            ErrorBanner(
              error is String ? error.toString() : messageFor(error!),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      TextButton(
        onPressed: busy ? null : save,
        child: Text(busy ? 'Menyimpan…' : 'Simpan ukuran'),
      ),
    ],
  );
}
