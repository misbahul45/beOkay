import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/validators.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _email = TextEditingController(text: widget.initialEmail ?? '');
  final _password = TextEditingController();
  bool _loading = false;
  bool _needsVerification = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _needsVerification = false;
    });
    try {
      await ref.read(authControllerProvider.notifier).signIn(email: _email.text.trim(), password: _password.text);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _needsVerification = error is ApiException && error.code == 'EMAIL_NOT_VERIFIED';
        _error = messageFor(error);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final expired = auth is AuthUnauthenticated && auth.sessionExpired;
    return PageScaffold(
      onBack: () => context.go(Routes.welcome),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PillButton(label: 'Masuk', loading: _loading, onPressed: _submit),
          const SizedBox(height: AppSpacing.xxs),
          TextButton(onPressed: () => context.go(Routes.register), child: Text('Belum punya akun? Buat akun', style: AppTypography.bodyStrong)),
        ],
      ),
      children: [
        Semantics(header: true, child: Text('Selamat Datang Kembali', style: AppTypography.headline)),
        const SizedBox(height: AppSpacing.xs),
        Text('Lanjutkan perjalanan kesehatanmu.', style: AppTypography.secondary),
        const SizedBox(height: AppSpacing.lg),
        if (expired) ...[
          const InfoCard(text: 'Sesimu sudah berakhir. Masuk kembali untuk melanjutkan.', tone: InfoTone.warning),
          const SizedBox(height: AppSpacing.md),
        ],
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              children: [
                AppTextField(
                  label: 'Email',
                  controller: _email,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  keyboardType: TextInputType.emailAddress,
                  validator: validateEmail,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Kata sandi',
                  controller: _password,
                  obscure: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                  validator: (value) => validateRequired(value, 'Kata sandi wajib diisi.'),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.go(Routes.forgotPassword),
            child: Text('Lupa kata sandi?', style: AppTypography.secondaryStrong),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _needsVerification
              ? InfoCard(
                  text: _error!,
                  tone: InfoTone.warning,
                  action: PillButton(
                    label: 'Kirim ulang tautan',
                    kind: PillButtonKind.secondary,
                    expand: false,
                    onPressed: () => context.go('${Routes.verifyEmail}?email=${Uri.encodeQueryComponent(_email.text.trim())}'),
                  ),
                )
              : ErrorBanner(_error!),
        ],
      ],
    );
  }
}
