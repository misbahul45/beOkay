import 'package:flutter/material.dart';

import '../../../../core/network/error_messages.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/info_card.dart';
import '../../../../core/widgets/page_scaffold.dart';
import '../../../../core/widgets/pill_button.dart';
import '../../data/nutrition_models.dart';
import '../../data/nutrition_repository.dart';
import 'scan_widgets.dart';

const _labels = {
  'calories': ('Energi', 'kkal'),
  'protein': ('Protein', 'g'),
  'fat': ('Lemak', 'g'),
  'carbohydrates': ('Karbohidrat', 'g'),
  'fiber': ('Serat', 'g'),
};

/// Layar periksa-sebelum-simpan untuk hasil kode batang dan label. Nilai bisa diubah; yang kosong
/// tetap kosong (tidak diganti 0). Disimpan sebagai makanan pribadi berstatus "estimasi".
class FoodReviewScreen extends StatefulWidget {
  const FoodReviewScreen({super.key, required this.candidate, required this.repository, required this.title, required this.provenance, this.notes = const [], this.requireName = false});
  final FoodCandidate candidate;
  final NutritionRepository repository;
  final String title, provenance;
  final List<String> notes;
  final bool requireName;
  @override
  State<FoodReviewScreen> createState() => _FoodReviewScreenState();
}

class _FoodReviewScreenState extends State<FoodReviewScreen> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.requireName ? '' : widget.candidate.name);
  late final fields = {
    for (final k in _labels.keys) k: TextEditingController(text: _fmt(widget.candidate.per100g[k])),
  };
  bool saving = false;
  Object? error;

  static String _fmt(num? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1));

  @override
  void dispose() {
    name.dispose();
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final c = widget.candidate;
      final trimmed = name.text.trim();
      final food = await widget.repository.saveFood({
        'name': c.brand == null || widget.requireName ? trimmed : '$trimmed (${c.brand})',
        'source': c.source,
        'sourceVersion': c.externalId,
        'status': 'estimated',
        'per100g': fields.map((k, v) => MapEntry(k, v.text.trim().isEmpty ? null : num.parse(v.text.trim().replaceAll(',', '.')))),
      });
      if (mounted) Navigator.pop(context, food);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unknown = fields.values.where((c) => c.text.trim().isEmpty).length;
    return PageScaffold(
      title: widget.title,
      onBack: () => Navigator.pop(context),
      bottom: PillButton(label: 'Simpan sebagai makanan', loading: saving, onPressed: save),
      children: [
        Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(alignment: Alignment.centerLeft, child: ProvenanceChip(widget.provenance)),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                label: 'Nama produk',
                hint: 'mis. Sereal gandum',
                controller: name,
                maxLength: 120,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Isi nama produk.' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Nilai per 100 g', style: AppTypography.secondaryStrong),
              const SizedBox(height: AppSpacing.xs),
              for (final e in _labels.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AppTextField(
                    label: '${e.value.$1} (${e.value.$2})',
                    hint: 'Kosong = belum diketahui',
                    controller: fields[e.key]!,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final n = num.tryParse(v.trim().replaceAll(',', '.'));
                      return n == null || n < 0 || n > 1000 ? 'Isi angka 0–1000 atau kosongkan.' : null;
                    },
                  ),
                ),
              if (unknown > 0) InfoCard(tone: InfoTone.neutral, text: '$unknown nilai dikosongkan karena tidak tersedia atau tidak terbaca. Itu berbeda dari nol.'),
              for (final n in widget.notes) ...[const SizedBox(height: AppSpacing.sm), InfoCard(tone: InfoTone.info, text: n)],
              if (error != null) ...[const SizedBox(height: AppSpacing.sm), ErrorBanner(messageFor(error!))],
            ],
          ),
        ),
      ],
    );
  }
}
