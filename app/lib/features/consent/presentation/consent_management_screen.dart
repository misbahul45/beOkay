import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/formatters.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/offline/sync_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/consent_controller.dart';
import '../data/consent_models.dart';
import 'consent_purpose_card.dart';

class ConsentManagementScreen extends ConsumerStatefulWidget {
  const ConsentManagementScreen({super.key});

  @override
  ConsumerState<ConsentManagementScreen> createState() =>
      _ConsentManagementScreenState();
}

class _ConsentManagementScreenState
    extends ConsumerState<ConsentManagementScreen> {
  String? _busy;
  String? _error;

  Future<void> _run(String purpose, Future<void> Function() action) async {
    setState(() {
      _busy = purpose;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _withdraw(PolicyPurpose purpose) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tarik persetujuan?'),
        content: Text(purpose.withdrawalEffect),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Tarik persetujuan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      purpose.purpose,
      () async {
        await ref.read(consentControllerProvider.notifier).withdraw([
          purpose.purpose,
        ]);
        // Catatan yang belum terkirim tidak boleh diproses setelah persetujuan ditarik.
        if (purpose.purpose == 'health_data_processing') {
          await ref.read(syncControllerProvider.notifier).clearForConsentWithdrawal();
        }
      },
    );
  }

  Future<void> _grant(ConsentPolicy policy, PolicyPurpose purpose) {
    return _run(
      purpose.purpose,
      () => ref
          .read(consentControllerProvider.notifier)
          .grant(
            policyVersion: policy.version,
            purposes: [purpose.purpose],
            source: 'settings',
          ),
    );
  }

  (String, InfoTone, IconData) _badge(ConsentStatus status) => switch (status) {
    ConsentStatus.granted => (
      'Aktif',
      InfoTone.info,
      Icons.check_circle_outline,
    ),
    ConsentStatus.withdrawn => (
      'Ditarik',
      InfoTone.warning,
      Icons.remove_circle_outline,
    ),
    ConsentStatus.reconsentRequired => (
      'Perlu persetujuan ulang',
      InfoTone.warning,
      Icons.refresh,
    ),
    ConsentStatus.notGiven => (
      'Belum diberikan',
      InfoTone.neutral,
      Icons.radio_button_unchecked,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final policy = ref.watch(consentPolicyProvider);
    final overview = ref.watch(consentControllerProvider);
    final combined =
        policy.hasValue && overview.hasValue && overview.value != null
        ? AsyncData((policy.requireValue, overview.requireValue!))
        : (policy.hasError
              ? AsyncError<(ConsentPolicy, ConsentOverview)>(
                  policy.error!,
                  policy.stackTrace!,
                )
              : (overview.hasError
                    ? AsyncError<(ConsentPolicy, ConsentOverview)>(
                        overview.error!,
                        overview.stackTrace!,
                      )
                    : const AsyncLoading<(ConsentPolicy, ConsentOverview)>()));
    return PageScaffold(
      title: 'Persetujuan Data',
      children: [
        Text(
          'Lihat tujuan pemrosesan, ubah persetujuanmu, dan baca riwayatnya. Perubahan langsung berlaku di server.',
          style: AppTypography.secondary,
        ),
        const SizedBox(height: AppSpacing.lg),
        AsyncBody<(ConsentPolicy, ConsentOverview)>(
          value: combined,
          onRetry: () {
            ref.invalidate(consentPolicyProvider);
            ref.invalidate(consentControllerProvider);
          },
          data: (data) {
            final (policyData, overviewData) = data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoCard(
                  text:
                      'Kebijakan versi ${policyData.version} (draf). Penarikan tidak otomatis menghapus data yang sudah tersimpan.',
                  tone: InfoTone.neutral,
                  icon: Icons.policy_outlined,
                ),
                const SizedBox(height: AppSpacing.md),
                for (final purpose in policyData.purposes) ...[
                  _purposeCard(
                    policyData,
                    purpose,
                    overviewData.of(purpose.purpose),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (_error != null) ...[
                  ErrorBanner(_error!),
                  const SizedBox(height: AppSpacing.md),
                ],
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  header: true,
                  child: Text(
                    'Riwayat persetujuan',
                    style: AppTypography.title,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (overviewData.history.isEmpty)
                  Text('Belum ada riwayat.', style: AppTypography.secondary)
                else
                  for (final item in overviewData.history.take(30))
                    _historyRow(policyData, item),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _purposeCard(
    ConsentPolicy policy,
    PolicyPurpose purpose,
    PurposeConsent? state,
  ) {
    final status = state?.status ?? ConsentStatus.notGiven;
    final (label, tone, icon) = _badge(status);
    final busy = _busy == purpose.purpose;
    final Widget action;
    if (status == ConsentStatus.granted) {
      action = PillButton(
        label: purpose.required ? 'Tarik persetujuan' : 'Matikan',
        kind: purpose.required
            ? PillButtonKind.danger
            : PillButtonKind.secondary,
        loading: busy,
        onPressed: () => purpose.required
            ? _withdraw(purpose)
            : _run(
                purpose.purpose,
                () => ref.read(consentControllerProvider.notifier).withdraw([
                  purpose.purpose,
                ]),
              ),
      );
    } else {
      action = PillButton(
        label: status == ConsentStatus.reconsentRequired
            ? 'Setujui versi terbaru'
            : (purpose.required ? 'Beri persetujuan' : 'Aktifkan'),
        loading: busy,
        onPressed: () => _grant(policy, purpose),
      );
    }
    return ConsentPurposeCard(
      purpose: purpose,
      badge: StatusBadge(label: label, tone: tone, icon: icon),
      footer: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: action,
      ),
    );
  }

  Widget _historyRow(ConsentPolicy policy, ConsentHistoryItem item) {
    final title =
        policy.purposes
            .where((p) => p.purpose == item.purpose)
            .map((p) => p.title)
            .firstOrNull ??
        item.purpose;
    final end = item.withdrawnAt == null
        ? 'Aktif'
        : 'Ditarik ${formatDate(item.withdrawnAt!)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        container: true,
        label:
            '$title. Diberikan ${formatDate(item.grantedAt)}, kebijakan ${item.policyVersion}. $end.',
        excludeSemantics: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.input),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.secondaryStrong),
              const SizedBox(height: 2),
              Text(
                'Diberikan ${formatDate(item.grantedAt)} · kebijakan v${item.policyVersion} · $end',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
