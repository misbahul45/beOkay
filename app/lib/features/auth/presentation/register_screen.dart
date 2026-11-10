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

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final email = _email.text.trim();
    try {
      await ref
          .read(authRepositoryProvider)
          .signUp(
            name: _name.text.trim(),
            email: email,
            password: _password.text,
          );
      if (!mounted) return;
      context.go(
        '${Routes.verifyEmail}?email=${Uri.encodeQueryComponent(email)}',
      );
    } catch (error) {
      if (mounted) setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      onBack: () => context.go(Routes.welcome),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PillButton(label: 'Buat Akun', loading: _loading, onPressed: _submit),
          const SizedBox(height: AppSpacing.xxs),
          TextButton(
            onPressed: () => context.go(Routes.login),
            child: Text(
              'Sudah punya akun? Masuk',
              style: AppTypography.bodyStrong,
            ),
          ),
        ],
      ),
      children: [
        Semantics(
          header: true,
          child: Text('Buat Akunmu', style: AppTypography.headline),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Mulai dengan membuat akun untuk menyimpan perjalanan kesehatanmu.',
          style: AppTypography.secondary,
        ),
        const SizedBox(height: AppSpacing.lg),
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              children: [
                AppTextField(
                  label: 'Nama',
                  hint: 'mis. Rina Putri',
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  keyboardType: TextInputType.name,
                  validator: validateName,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Email',
                  hint: 'nama@email.com',
                  controller: _email,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  keyboardType: TextInputType.emailAddress,
                  validator: validateEmail,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Kata sandi',
                  hint: 'Minimal 10 karakter',
                  controller: _password,
                  obscure: true,
                  helper: 'Minimal 10 karakter.',
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: validateNewPassword,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Ulangi kata sandi',
                  hint: 'Ketik ulang kata sandi',
                  controller: _confirm,
                  obscure: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onSubmitted: (_) => _submit(),
                  validator: (value) => value == _password.text
                      ? null
                      : 'Konfirmasi kata sandi belum sama.',
                ),
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          ErrorBanner(_error!),
        ],
      ],
    );
  }
}
