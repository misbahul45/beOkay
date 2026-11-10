import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/auth_controller.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  static const _cooldownSeconds = 60;
  Timer? _timer;
  int _remaining = 0;
  bool _sending = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _remaining = _cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _remaining -= 1);
      if (_remaining <= 0) timer.cancel();
    });
  }

  Future<void> _resend() async {
    setState(() {
      _sending = true;
      _message = null;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).resendVerification(widget.email);
      if (!mounted) return;
      setState(
        () => _message =
            'Jika email ini terdaftar dan belum terverifikasi, tautan baru sudah dikirim.',
      );
      _startCooldown();
    } catch (error) {
      if (mounted) setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      onBack: () => context.go(Routes.login),
      bottom: PillButton(
        label: 'Saya sudah membuka tautannya, masuk',
        onPressed: () => context.go(
          '${Routes.login}?email=${Uri.encodeQueryComponent(widget.email)}',
        ),
      ),
      children: [
        const SizedBox(height: AppSpacing.lg),
        Container(
          height: 72,
          width: 72,
          decoration: const BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
          ),
          child: const ExcludeSemantics(
            child: Icon(
              Icons.mail_outline_rounded,
              size: 34,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text('Periksa Emailmu', style: AppTypography.headline),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Kami telah mengirimkan tautan verifikasi untuk memastikan akunmu tetap aman.',
          style: AppTypography.secondary,
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.input),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(widget.email, style: AppTypography.bodyStrong),
        ),
        const SizedBox(height: AppSpacing.md),
        const InfoCard(
          text:
              'Akunmu baru dianggap terverifikasi setelah kamu membuka tautan di email. Tautan berlaku 1 jam.',
          tone: InfoTone.neutral,
        ),
        const SizedBox(height: AppSpacing.lg),
        PillButton(
          label: _remaining > 0
              ? 'Kirim ulang tautan ($_remaining dtk)'
              : 'Kirim ulang tautan',
          kind: PillButtonKind.secondary,
          loading: _sending,
          onPressed: _remaining > 0 ? null : _resend,
        ),
        if (_message != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            liveRegion: true,
            child: InfoCard(
              text: _message!,
              tone: InfoTone.info,
              icon: Icons.check_circle_outline,
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          ErrorBanner(_error!),
        ],
      ],
    );
  }
}
