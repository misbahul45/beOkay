import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/selection_card.dart';
import '../../../core/widgets/settings_group.dart';
import '../../../core/widgets/step_header.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../application/preferences_controller.dart';
import '../data/preferences_models.dart';
import 'timezone_picker.dart';

class PreferencesSetupScreen extends ConsumerStatefulWidget {
  const PreferencesSetupScreen({super.key});

  @override
  ConsumerState<PreferencesSetupScreen> createState() =>
      _PreferencesSetupScreenState();
}

class _PreferencesSetupScreenState
    extends ConsumerState<PreferencesSetupScreen> {
  String? _timezone;
  GlucoseUnit? _unit;
  bool _loading = false;
  String? _error;

  Future<void> _save() async {
    final current = ref.read(effectivePreferencesProvider);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(preferencesControllerProvider.notifier)
          .save(
            timezone: _timezone ?? current.timezone,
            glucoseUnit: _unit ?? current.glucoseUnit,
          );
      final status = ref.read(onboardingControllerProvider).value;
      if (mounted && status != null) {
        context.go(routeForOnboarding(status.state));
      }
    } catch (error) {
      if (mounted) setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(preferencesControllerProvider);
    final effective = ref.watch(effectivePreferencesProvider);
    final timezone = _timezone ?? effective.timezone;
    final unit = _unit ?? effective.glucoseUnit;
    return PageScaffold(
      showBack: false,
      bottom: PillButton(
        label: 'Simpan dan Lanjut',
        loading: _loading,
        onPressed: preferences.hasValue ? _save : null,
      ),
      children: [
        const StepHeader(current: 4, total: 4),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text('Sesuaikan Pengalamanmu', style: AppTypography.headline),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Pengaturan ini bisa diubah kapan saja di Profil › Pengaturan.',
          style: AppTypography.secondary,
        ),
        const SizedBox(height: AppSpacing.lg),
        AsyncBody<Preferences>(
          value: preferences,
          onRetry: () => ref.invalidate(preferencesControllerProvider),
          data: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bahasa', style: AppTypography.title),
              const SizedBox(height: AppSpacing.sm),
              const SelectionCard(
                title: 'Bahasa Indonesia',
                description:
                    'Bahasa lain menyusul setelah terjemahannya lengkap.',
                selected: true,
                onTap: null,
                enabled: false,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Zona Waktu', style: AppTypography.title),
              const SizedBox(height: AppSpacing.sm),
              SettingsGroup(
                children: [
                  SettingsRow(
                    title: timezoneLabel(timezone),
                    subtitle: timezone,
                    onTap: () async {
                      final picked = await showTimezonePicker(
                        context,
                        current: timezone,
                      );
                      if (picked != null && mounted) {
                        setState(() => _timezone = picked);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Satuan Glukosa', style: AppTypography.title),
              const SizedBox(height: AppSpacing.sm),
              SegmentedPills<GlucoseUnit>(
                options: [
                  for (final item in GlucoseUnit.values) (item, item.label),
                ],
                value: unit,
                onChanged: (value) => setState(() => _unit = value),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
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
