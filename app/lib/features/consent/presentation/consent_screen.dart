import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/step_header.dart';
import '../../auth/application/auth_controller.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../application/consent_controller.dart';
import '../data/consent_models.dart';
import 'consent_purpose_card.dart';

class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  final Set<String> _accepted = {};
  bool _loading = false;
  String? _error;

  Future<void> _submit(ConsentPolicy policy) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(consentControllerProvider.notifier).grant(
            policyVersion: policy.version,
            purposes: _accepted.toList(),
            source: 'onboarding',
          );
      final status = ref.read(onboardingControllerProvider).value;
      if (mounted && status != null) context.go(routeForOnboarding(status.state));
    } catch (error) {
      if (mounted) setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decline() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tanpa persetujuan wajib'),
        content: const Text('Tanpa persetujuan wajib, beOkay belum bisa menyimpan profil kesehatanmu. Kamu bisa kembali kapan saja untuk memberikannya.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Kembali')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Keluar dari akun')),
        ],
      ),
    );
    if (leave == true) await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final policy = ref.watch(consentPolicyProvider);
    final requiredPurposes = policy.value?.purposes.where((p) => p.required).map((p) => p.purpose).toSet() ?? const <String>{};
    final allRequired = requiredPurposes.isNotEmpty && requiredPurposes.every(_accepted.contains);
    return PageScaffold(
      showBack: false,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PillButton(
            label: 'Setuju dan Lanjutkan',
            loading: _loading,
            onPressed: allRequired && policy.value != null ? () => _submit(policy.value!) : null,
          ),
          TextButton(onPressed: _decline, child: Text('Tidak sekarang', style: AppTypography.bodyStrong)),
        ],
      ),
      children: [
        const StepHeader(current: 1, total: 4),
        const SizedBox(height: AppSpacing.lg),
        Semantics(header: true, child: Text('Datamu, Kendalimu.', style: AppTypography.headline)),
        const SizedBox(height: AppSpacing.xs),
        Text('Pelajari bagaimana informasi kesehatanmu digunakan dan pilih persetujuan yang sesuai.', style: AppTypography.secondary),
        const SizedBox(height: AppSpacing.lg),
        AsyncBody<ConsentPolicy>(
          value: policy,
          skeletonRows: 3,
          onRetry: () => ref.invalidate(consentPolicyProvider),
          data: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoCard(title: 'Kebijakan v${data.version} (draf)', text: data.summary, tone: InfoTone.neutral, icon: Icons.policy_outlined),
              const SizedBox(height: AppSpacing.md),
              for (final purpose in data.purposes) ...[
                ConsentPurposeCard(
                  purpose: purpose,
                  footer: _AcceptRow(
                    label: purpose.required ? 'Saya menyetujui tujuan wajib ini' : 'Saya menyetujui tujuan opsional ini',
                    value: _accepted.contains(purpose.purpose),
                    onChanged: (checked) => setState(() => checked ? _accepted.add(purpose.purpose) : _accepted.remove(purpose.purpose)),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Text('Kamu bisa menarik persetujuan kapan saja di Profil › Pengaturan › Persetujuan data.', style: AppTypography.caption),
            ],
          ),
        ),
        if (_error != null) ...[const SizedBox(height: AppSpacing.md), ErrorBanner(_error!)],
      ],
    );
  }
}

class _AcceptRow extends StatelessWidget {
  const _AcceptRow({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      checked: value,
      label: label,
      excludeSemantics: true,
      onTap: () => onChanged(!value),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.input),
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 26,
                width: 26,
                decoration: BoxDecoration(
                  color: value ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: value ? AppColors.primary : AppColors.overlay, width: 1.5),
                ),
                child: value ? const Icon(Icons.check, size: 18, color: AppColors.onPrimary) : null,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(label, style: AppTypography.secondaryStrong)),
            ],
          ),
        ),
      ),
    );
  }
}
