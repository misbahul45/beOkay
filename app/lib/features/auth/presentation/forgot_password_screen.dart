import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/validators.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/auth_controller.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).requestPasswordReset(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (error) {
      if (mounted) setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      onBack: () => context.go(Routes.login),
      bottom: _sent
          ? PillButton(label: 'Kembali ke Masuk', onPressed: () => context.go(Routes.login))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PillButton(label: 'Kirim Tautan', loading: _loading, onPressed: _submit),
                const SizedBox(height: AppSpacing.xxs),
                TextButton(onPressed: () => context.go(Routes.login), child: Text('Kembali ke Masuk', style: AppTypography.bodyStrong)),
              ],
            ),
      children: [
        Semantics(header: true, child: Text('Lupa Kata Sandi?', style: AppTypography.headline)),
        const SizedBox(height: AppSpacing.xs),
        Text('Masukkan email akunmu. Kami akan mengirim tautan untuk mengatur ulang kata sandi.', style: AppTypography.secondary),
        const SizedBox(height: AppSpacing.lg),
        if (_sent)
          const InfoCard(
            title: 'Periksa emailmu',
            text: 'Jika email itu terdaftar, tautan untuk mengatur ulang kata sandi sudah dikirim. Tautan berlaku 1 jam.',
            icon: Icons.mark_email_read_outlined,
          )
        else
          Form(
            key: _form,
            child: AppTextField(
              label: 'Email',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              onSubmitted: (_) => _submit(),
              validator: validateEmail,
            ),
          ),
        if (_error != null) ...[const SizedBox(height: AppSpacing.md), ErrorBanner(_error!)],
      ],
    );
  }
}
