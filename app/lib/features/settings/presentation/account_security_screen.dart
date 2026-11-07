import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/formatters.dart';
import '../../../core/format/validators.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/settings_group.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/session_user.dart';

final sessionsProvider = FutureProvider.autoDispose<List<DeviceSession>>((ref) => ref.watch(authRepositoryProvider).listSessions());

class AccountSecurityScreen extends ConsumerStatefulWidget {
  const AccountSecurityScreen({super.key});

  @override
  ConsumerState<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends ConsumerState<AccountSecurityScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _changing = false;
  bool _revoking = false;
  String? _passwordError;
  String? _sessionError;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _changing = true;
      _passwordError = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authRepositoryProvider).changePassword(currentPassword: _current.text, newPassword: _next.text);
      _current.clear();
      _next.clear();
      _confirm.clear();
      messenger.showSnackBar(const SnackBar(content: Text('Kata sandi diperbarui. Sesi lain dikeluarkan.')));
      ref.invalidate(sessionsProvider);
    } catch (error) {
      if (mounted) setState(() => _passwordError = messageFor(error));
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  Future<void> _revokeOthers() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluarkan sesi lain?'),
        content: const Text('Semua perangkat lain akan keluar. Perangkat ini tetap masuk.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Keluarkan')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _revoking = true;
      _sessionError = null;
    });
    try {
      await ref.read(authRepositoryProvider).revokeOtherSessions();
      ref.invalidate(sessionsProvider);
    } catch (error) {
      if (mounted) setState(() => _sessionError = messageFor(error));
    } finally {
      if (mounted) setState(() => _revoking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final user = auth is AuthAuthenticated ? auth.user : null;
    final sessions = ref.watch(sessionsProvider);
    return PageScaffold(
      title: 'Keamanan Akun',
      children: [
        SettingsGroup(
          title: 'Akun',
          children: [
            SettingsRow(
              icon: Icons.alternate_email,
              title: 'Email',
              value: user?.email ?? '',
              trailing: StatusBadge(
                label: (user?.emailVerified ?? false) ? 'Terverifikasi' : 'Belum terverifikasi',
                icon: (user?.emailVerified ?? false) ? Icons.check : Icons.warning_amber_rounded,
                tone: (user?.emailVerified ?? false) ? InfoTone.info : InfoTone.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('UBAH KATA SANDI', style: AppTypography.overline),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.cardRadius, boxShadow: AppShadows.soft),
          child: Form(
            key: _form,
            child: Column(
              children: [
                AppTextField(label: 'Kata sandi saat ini', controller: _current, obscure: true, autofillHints: const [AutofillHints.password], validator: (value) => validateRequired(value, 'Isi kata sandi saat ini.')),
                const SizedBox(height: AppSpacing.md),
                AppTextField(label: 'Kata sandi baru', controller: _next, obscure: true, helper: 'Minimal 10 karakter.', autofillHints: const [AutofillHints.newPassword], validator: validateNewPassword),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Ulangi kata sandi baru',
                  controller: _confirm,
                  obscure: true,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (value) => value == _next.text ? null : 'Konfirmasi kata sandi belum sama.',
                ),
                if (_passwordError != null) ...[const SizedBox(height: AppSpacing.md), ErrorBanner(_passwordError!)],
                const SizedBox(height: AppSpacing.md),
                PillButton(label: 'Simpan Kata Sandi', loading: _changing, onPressed: _changePassword),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('SESI AKTIF', style: AppTypography.overline),
        const SizedBox(height: AppSpacing.sm),
        AsyncBody<List<DeviceSession>>(
          value: sessions,
          skeletonRows: 2,
          onRetry: () => ref.invalidate(sessionsProvider),
          data: (items) => Column(
            children: [
              SettingsGroup(
                children: [
                  for (final session in items)
                    SettingsRow(
                      icon: session.isCurrent ? Icons.phone_android : Icons.devices_other,
                      title: session.isCurrent ? 'Perangkat ini' : 'Perangkat lain',
                      subtitle: 'Masuk ${formatDate(session.createdAt)}${session.userAgent.isEmpty ? '' : ' · ${_shortAgent(session.userAgent)}'}',
                      trailing: session.isCurrent ? const StatusBadge(label: 'Sekarang', icon: Icons.check, tone: InfoTone.info) : null,
                    ),
                ],
              ),
              if (items.any((item) => !item.isCurrent)) ...[
                const SizedBox(height: AppSpacing.sm),
                PillButton(label: 'Keluarkan sesi lain', kind: PillButtonKind.secondary, loading: _revoking, onPressed: _revokeOthers),
              ],
              if (_sessionError != null) ...[const SizedBox(height: AppSpacing.sm), ErrorBanner(_sessionError!)],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        PillButton(
          label: 'Keluar dari perangkat ini',
          kind: PillButtonKind.danger,
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
        ),
      ],
    );
  }

  String _shortAgent(String agent) => agent.length <= 32 ? agent : '${agent.substring(0, 32)}…';
}
