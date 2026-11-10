import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../food_preferences/data/food_preferences_repository.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/pill_button.dart';
import '../data/nutrition_models.dart';
import '../data/nutrition_repository.dart';
import 'scan/scan_hub.dart';

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
  bool loading = false, searched = false, loadingExternal = false;
  ExternalSearch? external;
  List<ReferenceFood> reference = [];
  PreferenceChecks checks = PreferenceChecks.empty;
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
          reference = [];
          checks = PreferenceChecks.empty;
        });
        unawaited(enrich(q, request));
      }
    } catch (e) {
      if (mounted && request == generation) setState(() => error = e);
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  /// Tambahan yang tidak boleh menghalangi pencarian utama: referensi TKPI dan pengecekan alergi/preferensi.
  Future<void> enrich(String q, int request) async {
    List<ReferenceFood> ref = [];
    try {
      ref = await widget.repository.searchReference(q);
    } catch (_) {}
    if (!mounted || request != generation) return;
    setState(() => reference = ref);
    await recheck(request);
  }

  Future<void> recheck(int request) async {
    final names = [
      ...items.map((f) => f.name),
      ...reference.map((r) => r.name),
      ...?external?.items.map(
        (c) => c.brand == null ? c.name : '${c.name} · ${c.brand}',
      ),
    ];
    try {
      final c = await widget.repository.preferenceChecks(names);
      if (mounted && request == generation) setState(() => checks = c);
    } catch (_) {}
  }

  /// Memakai makanan hasil pencarian; bila cocok dengan kendala keras, minta konfirmasi dulu.
  Future<bool> confirmIfExcluded(String name) async {
    final c = checks.of(name);
    if (c == null || !c.excluded) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cocok dengan kendalamu'),
        content: Text(
          '"$name" tampaknya mengandung ${c.labels.join(', ')} (dugaan dari nama). Tetap gunakan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tetap gunakan'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Widget? preferenceLine(String name) {
    final c = checks.of(name);
    if (c == null) return null;
    if (c.excluded) {
      return Text(
        'Perhatian: cocok dengan ${c.labels.join(', ')} (dugaan dari nama)',
        style: const TextStyle(
          color: AppColors.errorForeground,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    if (c.warning) {
      return Text(
        'Kamu tidak suka: ${c.labels.join(', ')}',
        style: const TextStyle(color: AppColors.warningForeground),
      );
    }
    return null;
  }

  Future<void> useReference(ReferenceFood r) async {
    if (!await confirmIfExcluded(r.name)) return;
    try {
      final food = await widget.repository.saveFood({
        'name': r.name,
        'source': r.source,
        'sourceVersion': r.code,
        'status': 'estimated',
        'per100g': r.per100g,
      });
      if (mounted) Navigator.pop(context, food);
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> searchExternal() async {
    final q = query.text.trim();
    if (q.length < 2) return;
    setState(() {
      loadingExternal = true;
      error = null;
    });
    try {
      final found = await widget.repository.searchExternal(q);
      if (mounted) setState(() => external = found);
      await recheck(generation);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loadingExternal = false);
    }
  }

  Future<void> openScan() async {
    final outcome = await showScanHub(context, widget.repository);
    if (!mounted || outcome == null) return;
    if (outcome.food != null) {
      Navigator.pop(context, outcome.food);
    } else if (outcome.query != null) {
      query.text = outcome.query!;
      await search();
    }
  }

  /// Menyimpan kandidat sebagai makanan pribadi berstatus estimasi; nilai yang tidak ada tetap kosong.
  Future<void> useCandidate(FoodCandidate c) async {
    if (!await confirmIfExcluded(
      c.brand == null ? c.name : '${c.name} · ${c.brand}',
    )) {
      return;
    }
    try {
      final food = await widget.repository.saveFood({
        'name': c.brand == null ? c.name : '${c.name} (${c.brand})',
        'source': c.source,
        'sourceVersion': c.externalId,
        'status': 'estimated',
        'per100g': c.per100g,
      });
      if (mounted) Navigator.pop(context, food);
    } catch (e) {
      if (mounted) setState(() => error = e);
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
            label: 'Nama makanan',
            hint: 'mis. tempe, nasi putih',
            controller: query,
            onSubmitted: (_) => search(),
          ),
          const SizedBox(height: 12),
          PillButton(label: 'Cari', loading: loading, onPressed: search),
          const SizedBox(height: 8),
          PillButton(
            label: 'Pindai atau foto',
            kind: PillButtonKind.secondary,
            icon: Icons.qr_code_scanner_rounded,
            onPressed: openScan,
          ),
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
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${food.source}\n${food.status == 'estimated' ? 'Perkiraan' : 'Dicatat sendiri'} · per 100 gram',
                  ),
                  ?preferenceLine(food.name),
                ],
              ),
              onTap: () async {
                if (await confirmIfExcluded(food.name) && context.mounted) {
                  Navigator.pop(context, food);
                }
              },
            ),
          if (reference.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Dari Tabel Komposisi Pangan Indonesia',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final r in reference)
              ListTile(
                title: Text(r.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(r.summary), ?preferenceLine(r.name)],
                ),
                onTap: () => useReference(r),
              ),
          ],
          if (searched && checks.hasStrictConstraints)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Alergi hanya dicek dari nama makanan. Baca label atau tanyakan penjualnya.',
              ),
            ),
          if (searched) ...[
            const SizedBox(height: 12),
            PillButton(
              label: 'Cari juga di sumber luar',
              kind: PillButtonKind.secondary,
              loading: loadingExternal,
              onPressed: searchExternal,
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Mencari di Open Food Facts dan USDA. Hasilnya perkiraan.',
              ),
            ),
          ],
          if (external != null) ...[
            if (external!.status != 'OK')
              ErrorBanner(
                external!.status == 'UNAVAILABLE'
                    ? 'Sumber luar tidak dapat dihubungi sekarang.'
                    : 'Sebagian sumber luar tidak dapat dihubungi.',
              ),
            if (external!.items.isEmpty && external!.status == 'OK')
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Tidak ada hasil di sumber luar.'),
              ),
            for (final c in external!.items)
              ListTile(
                title: Text(
                  c.brand == null ? c.name : '${c.name} · ${c.brand}',
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${c.source} · ${c.completenessLabel} · per 100 g'),
                    ?preferenceLine(
                      c.brand == null ? c.name : '${c.name} · ${c.brand}',
                    ),
                  ],
                ),
                onTap: () => useCandidate(c),
              ),
          ],
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
              hint: 'mis. nasi pecel',
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
