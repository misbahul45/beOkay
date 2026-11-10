import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pill_button.dart';
import 'gtin.dart';

/// Pembangun kamera; diganti saat uji karena kamera tidak tersedia di tes widget.
typedef CameraBuilder =
    Widget Function(
      BuildContext context,
      void Function(String code) onCode,
      MobileScannerController? controller,
    );

Widget _deviceCamera(
  BuildContext context,
  void Function(String) onCode,
  MobileScannerController? controller,
) => MobileScanner(
  controller: controller,
  onDetect: (capture) {
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null) onCode(v);
    }
  },
  errorBuilder: (context, error) => const _CameraUnavailable(),
);

/// Layar pemindai kode batang. Pemindaian terjadi di perangkat (ML Kit); yang keluar hanya kode angkanya.
/// Mengembalikan kode GTIN yang lolos pemeriksaan digit, atau null bila dibatalkan.
class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({
    super.key,
    this.cameraBuilder = _deviceCamera,
    this.useController = true,
  });
  final CameraBuilder cameraBuilder;
  final bool useController;
  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen>
    with WidgetsBindingObserver {
  MobileScannerController? controller;
  bool done = false, torch = false;
  String? hint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.useController) {
      controller = MobileScannerController(
        formats: const [
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
        ],
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = controller;
    if (c == null) return;
    if (state == AppLifecycleState.resumed) {
      c.start();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      c.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    super.dispose();
  }

  void accept(String code) {
    if (done) return;
    if (!validGtin(code)) {
      setState(
        () => hint = 'Kode terbaca tetapi tidak valid. Coba arahkan ulang.',
      );
      return;
    }
    done = true;
    Navigator.pop(context, code);
  }

  Future<void> manual() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _ManualCodeDialog(),
    );
    if (code != null) accept(code);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0B1B1F),
    appBar: AppBar(
      backgroundColor: const Color(0xFF0B1B1F),
      foregroundColor: Colors.white,
      title: const Text('Pindai kode batang'),
      titleTextStyle: AppTypography.bodyStrong.copyWith(color: Colors.white),
      iconTheme: const IconThemeData(color: Colors.white),
      actions: [
        if (controller != null)
          IconButton(
            tooltip: torch ? 'Matikan senter' : 'Nyalakan senter',
            icon: Icon(
              torch ? Icons.flash_on_rounded : Icons.flash_off_rounded,
            ),
            onPressed: () async {
              await controller!.toggleTorch();
              if (mounted) setState(() => torch = !torch);
            },
          ),
      ],
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Column(
          children: [
            Text(
              'Arahkan kamera ke kode batang di kemasan. Pemindaian terjadi di perangkat; foto tidak dikirim.',
              style: AppTypography.secondary.copyWith(color: AppColors.overlay),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    widget.cameraBuilder(context, accept, controller),
                    const IgnorePointer(child: Center(child: _Viewfinder())),
                  ],
                ),
              ),
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  hint!,
                  style: AppTypography.secondary.copyWith(color: Colors.white),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            PillButton(
              label: 'Ketik kode manual',
              kind: PillButtonKind.secondary,
              icon: Icons.keyboard_rounded,
              onPressed: manual,
            ),
          ],
        ),
      ),
    ),
  );
}

class _Viewfinder extends StatelessWidget {
  const _Viewfinder();
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Bingkai pemindai kode batang',
    child: Container(
      width: 260,
      height: 150,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.aqua, width: 3),
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: Container(height: 2, width: 220, color: AppColors.emerald),
    ),
  );
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable();
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFF1B3238),
    padding: const EdgeInsets.all(24),
    alignment: Alignment.center,
    child: Text(
      'Kamera tidak bisa dipakai. Izinkan akses kamera di pengaturan perangkat, atau ketik kode secara manual.',
      textAlign: TextAlign.center,
      style: AppTypography.body.copyWith(color: Colors.white),
    ),
  );
}

class _ManualCodeDialog extends StatefulWidget {
  const _ManualCodeDialog();
  @override
  State<_ManualCodeDialog> createState() => _ManualCodeDialogState();
}

class _ManualCodeDialogState extends State<_ManualCodeDialog> {
  final c = TextEditingController();
  String? error;
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  void submit() {
    final v = c.text.trim();
    if (!validGtin(v)) {
      setState(
        () => error =
            'Kode tidak valid. Periksa 8, 12, 13, atau 14 angka di bawah kode batang.',
      );
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ketik kode batang'),
    content: TextField(
      controller: c,
      autofocus: true,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: 'Kode batang',
        hintText: 'mis. 8999999999999',
        errorText: error,
      ),
      onSubmitted: (_) => submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(onPressed: submit, child: const Text('Cari')),
    ],
  );
}
