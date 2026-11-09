import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/error_messages.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/info_card.dart';
import '../../data/nutrition_models.dart';
import '../../data/nutrition_repository.dart';
import 'barcode_scan_screen.dart';
import 'food_image_source.dart';
import 'food_review_screen.dart';
import 'photo_result_screen.dart';
import 'scan_widgets.dart';

export 'photo_result_screen.dart' show ScanOutcome;

/// Membuka pilihan metode pencatatan (kode batang, foto label, foto makanan). Mengembalikan makanan
/// yang tersimpan atau kata kunci pencarian; null bila dibatalkan atau pengguna memilih cari manual.
Future<ScanOutcome?> showScanHub(BuildContext context, NutritionRepository repository, {CameraBuilder? cameraBuilder}) =>
    showModalBottomSheet<ScanOutcome>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.background,
      builder: (_) => ScanHub(repository: repository, cameraBuilder: cameraBuilder),
    );

class ScanHub extends ConsumerStatefulWidget {
  const ScanHub({super.key, required this.repository, this.cameraBuilder});
  final NutritionRepository repository;
  final CameraBuilder? cameraBuilder;
  @override
  ConsumerState<ScanHub> createState() => _ScanHubState();
}

class _ScanHubState extends ConsumerState<ScanHub> {
  String? error;

  void finish(ScanOutcome? o) {
    if (mounted && o != null) Navigator.pop(context, o);
  }

  Future<void> guard(Future<void> Function() job) async {
    setState(() => error = null);
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => error = messageFor(e));
    }
  }

  Future<void> barcode() => guard(() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => widget.cameraBuilder == null ? const BarcodeScanScreen() : BarcodeScanScreen(cameraBuilder: widget.cameraBuilder!, useController: false)),
    );
    if (code == null || !mounted) return;
    final r = await runWithProgress(context, 'Mencari produk…', () => widget.repository.barcode(code));
    if (!mounted) return;
    switch (r.status) {
      case 'FOUND':
        final food = await Navigator.push<FoodReference>(
          context,
          MaterialPageRoute(
            builder: (_) => FoodReviewScreen(
              candidate: r.candidate!,
              repository: widget.repository,
              title: 'Periksa produk',
              provenance: 'Dari Open Food Facts · Estimasi',
              notes: const ['Data produk dikumpulkan komunitas dan bisa keliru. Cocokkan dengan label kemasan.'],
            ),
          ),
        );
        if (food != null) finish(ScanOutcome.food(food));
      case 'NOT_FOUND':
        setState(() => error = 'Produk dengan kode $code belum ada di Open Food Facts. Coba “Foto label gizi” atau isi manual.');
      default:
        setState(() => error = 'Sumber data produk tidak dapat dihubungi sekarang. Coba lagi nanti.');
    }
  });

  Future<Uint8List?> _capture() async {
    final picker = ref.read(foodImagePickerProvider);
    final camera = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Ambil foto'), onTap: () => Navigator.pop(context, true)),
          ListTile(leading: const Icon(Icons.photo_library_rounded), title: const Text('Pilih dari galeri'), onTap: () => Navigator.pop(context, false)),
        ]),
      ),
    );
    if (camera == null) return null;
    return picker.capture(camera: camera);
  }

  Future<void> label() => guard(() async {
    final bytes = await _capture();
    if (bytes == null || !mounted) return;
    if (!await confirmImageUpload(context, subject: 'label gizi')) return;
    if (!mounted) return;
    final r = await runWithProgress(context, 'Membaca label…', () => widget.repository.scanLabel(bytes));
    if (!mounted) return;
    if (r.status == 'UNAVAILABLE') {
      setState(() => error = r.code == 'PROVIDER_NOT_CONFIGURED' ? 'Pembaca label belum diaktifkan di server.' : 'Pembaca gambar tidak dapat dihubungi. Coba lagi nanti.');
      return;
    }
    if (r.status == 'NO_NUTRITION' || r.candidate == null) {
      setState(() => error = 'Tabel nilai gizi tidak terbaca. Foto lebih dekat dan terang, atau isi manual.');
      return;
    }
    final notes = <String>[
      if (r.basis == 'per_serving' && r.servingGrams != null) 'Dihitung dari takaran saji ${r.servingGrams} g. Bandingkan dengan kemasan.',
      if (r.basis == 'unknown') 'Dasar nilai (per 100 g atau per sajian) tidak jelas, jadi tidak dihitung otomatis. Isi sesuai kemasan.',
      'Angka yang salah baca bisa kamu ubah sebelum disimpan.',
    ];
    final food = await Navigator.push<FoodReference>(
      context,
      MaterialPageRoute(
        builder: (_) => FoodReviewScreen(
          candidate: r.candidate!,
          repository: widget.repository,
          title: 'Periksa hasil label',
          provenance: 'Dibaca dari foto · Perlu kamu periksa',
          notes: notes,
          requireName: true,
        ),
      ),
    );
    if (food != null) finish(ScanOutcome.food(food));
  });

  Future<void> photo() => guard(() async {
    final bytes = await _capture();
    if (bytes == null || !mounted) return;
    if (!await confirmImageUpload(context, subject: 'makanan')) return;
    if (!mounted) return;
    final r = await runWithProgress(context, 'Mengenali makanan…', () => widget.repository.scanPhoto(bytes));
    if (!mounted) return;
    if (r.status == 'UNAVAILABLE') {
      setState(() => error = r.code == 'PROVIDER_NOT_CONFIGURED' ? 'Pengenal foto belum diaktifkan di server.' : 'Pengenal foto tidak dapat dihubungi. Coba lagi nanti.');
      return;
    }
    if (r.status == 'NOT_FOOD' || r.items.isEmpty) {
      setState(() => error = 'Tidak ada makanan yang terlihat jelas. Coba foto dari atas dengan cahaya cukup, atau cari manual.');
      return;
    }
    final o = await Navigator.push<ScanOutcome>(context, MaterialPageRoute(builder: (_) => PhotoResultScreen(scan: r)));
    finish(o);
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text('Catat makanan', style: AppTypography.heading)),
        const SizedBox(height: 4),
        Text('Pilih cara yang paling mudah. Kamu selalu bisa memeriksa dan mengubah hasilnya.', style: AppTypography.secondary),
        const SizedBox(height: AppSpacing.md),
        MethodCard(icon: Icons.qr_code_scanner_rounded, tint: AppColors.glucoseTint, ink: AppColors.glucoseInk, title: 'Pindai kode batang', subtitle: 'Cocokkan produk kemasan. Dibaca di perangkat, tanpa mengirim foto.', onTap: barcode),
        const SizedBox(height: AppSpacing.xs),
        MethodCard(icon: Icons.document_scanner_rounded, tint: AppColors.mealTint, ink: AppColors.mealInk, title: 'Foto label gizi', subtitle: 'Baca tabel nilai gizi dari foto. Kamu periksa angkanya sebelum disimpan.', onTap: label),
        const SizedBox(height: AppSpacing.xs),
        MethodCard(icon: Icons.photo_camera_rounded, tint: AppColors.activityTint, ink: AppColors.activityInk, title: 'Foto makanan', subtitle: 'Kenali nama makanan. Berat dan gizi kamu tentukan sendiri.', onTap: photo),
        const SizedBox(height: AppSpacing.xs),
        MethodCard(icon: Icons.search_rounded, tint: AppColors.accent, ink: AppColors.brand, title: 'Cari manual', subtitle: 'Ketik nama dari katalog atau tambah makanan pribadi.', onTap: () => Navigator.pop(context)),
        if (error != null) ...[const SizedBox(height: AppSpacing.sm), ErrorBanner(error!)],
        const SizedBox(height: AppSpacing.md),
        const InfoCard(tone: InfoTone.info, text: 'Foto dikirim ke layanan pembaca gambar hanya saat kamu menyetujuinya, dan tidak disimpan di server.'),
      ],
    ),
  );
}
