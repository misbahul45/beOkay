import 'package:flutter/material.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/pill_button.dart';
import '../data/nutrition_models.dart';
import '../data/nutrition_repository.dart';

Future<FoodReference?> pickFood(
  BuildContext context,
  NutritionRepository repository,
) => showModalBottomSheet<FoodReference>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => FoodPicker(repository: repository),
);

class FoodPicker extends StatefulWidget {
  const FoodPicker({super.key, required this.repository});
  final NutritionRepository repository;
  @override
  State<FoodPicker> createState() => _FoodPickerState();
}

class _FoodPickerState extends State<FoodPicker> {
  final query = TextEditingController();
  List<FoodReference> items = [];
  Object? error;
  bool loading = false, searched = false;
  int generation = 0;
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> search() async {
    final q = query.text.trim();
    if (q.length < 2) {
      setState(() => error = 'Ketik minimal dua karakter.');
      return;
    }
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final found = await widget.repository.search(q);
      if (mounted && request == generation) {
        setState(() {
          items = found;
          searched = true;
        });
      }
    } catch (e) {
      if (mounted && request == generation) setState(() => error = e);
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      24,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cari makanan',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Nama makanan di katalog',
            controller: query,
            onSubmitted: (_) => search(),
          ),
          const SizedBox(height: 12),
          PillButton(label: 'Cari', loading: loading, onPressed: search),
          if (error != null)
            ErrorBanner(
              error is String ? error.toString() : messageFor(error!),
            ),
          if (searched && items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Belum ditemukan. Tambahkan makanan pribadi atau catat nama tanpa nilai gizi.',
              ),
            ),
          for (final food in items)
            ListTile(
              title: Text(food.name),
              subtitle: Text(
                '${food.source}\n${food.status == 'estimated' ? 'Estimasi' : 'Dilaporkan pengguna'} · per 100 g',
              ),
              onTap: () => Navigator.pop(context, food),
            ),
          const SizedBox(height: 12),
          PillButton(
            label: 'Tambah makanan pribadi',
            kind: PillButtonKind.secondary,
            onPressed: () async {
              final food = await showDialog<FoodReference>(
                context: context,
                builder: (_) => FoodEditor(repository: widget.repository),
              );
              if (food != null && context.mounted) Navigator.pop(context, food);
            },
          ),
        ],
      ),
    ),
  );
}

class FoodEditor extends StatefulWidget {
  const FoodEditor({super.key, required this.repository});
  final NutritionRepository repository;
  @override
  State<FoodEditor> createState() => _FoodEditorState();
}

class _FoodEditorState extends State<FoodEditor> {
  final form = GlobalKey<FormState>(),
      name = TextEditingController(),
      source = TextEditingController();
  final nutrientFields = {
    for (final key in nutrientLabels.keys) key: TextEditingController(),
  };
  bool busy = false, estimated = false;
  Object? error;
  @override
  void dispose() {
    name.dispose();
    source.dispose();
    for (final c in nutrientFields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final food = await widget.repository.saveFood({
        'name': name.text.trim(),
        'source': source.text.trim(),
        'status': estimated ? 'estimated' : 'user_reported',
        'per100g': nutrientFields.map(
          (key, c) => MapEntry(
            key,
            c.text.trim().isEmpty
                ? null
                : num.parse(c.text.trim().replaceAll(',', '.')),
          ),
        ),
      });
      if (mounted) Navigator.pop(context, food);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Makanan pribadi'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Isi nilai per 100 g dari sumber yang kamu miliki. Kosongkan nilai yang belum diketahui.',
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Nama makanan',
              controller: name,
              maxLength: 120,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Isi nama makanan.' : null,
            ),
            const SizedBox(height: 12),
            AppTextField(
              label: 'Sumber nilai gizi',
              controller: source,
              maxLength: 160,
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Isi sumber, misalnya label kemasan.'
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nilai merupakan estimasi'),
              value: estimated,
              onChanged: busy ? null : (v) => setState(() => estimated = v),
            ),
            for (final entry in nutrientFields.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppTextField(
                  label:
                      '${nutrientLabels[entry.key]} per 100 g (${entry.key == 'calories' ? 'kkal' : 'g'})',
                  controller: entry.value,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final n = num.tryParse(v.replaceAll(',', '.'));
                    return n == null || !n.isFinite || n < 0 || n > 10000
                        ? 'Isi angka 0–10000 atau kosongkan.'
                        : null;
                  },
                ),
              ),
            if (error != null) ErrorBanner(messageFor(error!)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      TextButton(
        onPressed: busy ? null : save,
        child: Text(busy ? 'Menyimpan…' : 'Simpan makanan pribadi'),
      ),
    ],
  );
}
