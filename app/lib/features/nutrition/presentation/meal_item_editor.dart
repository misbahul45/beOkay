import 'package:flutter/material.dart';
import '../../../core/widgets/app_text_field.dart';
import '../data/nutrition_models.dart';

class MealItemEditor extends StatefulWidget {
  const MealItemEditor({super.key, this.initial, this.food});
  final MealItemDraft? initial;
  final FoodReference? food;
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
        : num.tryParse(grams.text.trim().replaceAll(',', '.'));
    Navigator.pop(
      context,
      MealItemDraft(
        id: widget.initial?.id,
        foodId: widget.initial?.foodId ?? widget.food?.id,
        name: name.text.trim(),
        quantity: num.parse(quantity.text.replaceAll(',', '.')),
        unit: unit,
        grams: g,
        gramsBasis: g == null ? null : 'user_estimate',
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
            if (unit != 'g')
              AppTextField(
                label: 'Total gram perkiraan (opsional)',
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
