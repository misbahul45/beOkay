import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/validators.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/router/redirect.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/discard_guard.dart';
import '../../../core/widgets/domain_style.dart';
import '../../../core/widgets/form_kit.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/selection_card.dart';
import '../../../core/widgets/step_header.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../application/health_controller.dart';
import '../data/health_models.dart';

class HealthProfileScreen extends ConsumerWidget {
  const HealthProfileScreen({super.key, required this.onboarding});

  final bool onboarding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthControllerProvider);
    final loaded = health.isLoading || health.hasError ? null : health.value;
    if (loaded != null) {
      return _HealthForm(profile: loaded, onboarding: onboarding);
    }
    final error = health.error;
    final consentMissing =
        error is ApiException && error.code == 'CONSENT_REQUIRED';
    return PageScaffold(
      title: onboarding ? null : 'Profil Kesehatan',
      showBack: !onboarding,
      children: [
        if (consentMissing)
          InfoCard(
            tone: InfoTone.warning,
            title: 'Persetujuan diperlukan',
            text:
                'Profil kesehatan hanya bisa dibuka bila persetujuan pencatatan data kesehatan aktif.',
            action: PillButton(
              label: 'Tinjau persetujuan',
              kind: PillButtonKind.secondary,
              expand: false,
              onPressed: () => context.push(Routes.consentManagement),
            ),
          )
        else
          AsyncBody<HealthProfile?>(
            value: health,
            onRetry: () => ref.invalidate(healthControllerProvider),
            data: (_) => const SkeletonList(),
          ),
      ],
    );
  }
}

class _HealthForm extends ConsumerStatefulWidget {
  const _HealthForm({required this.profile, required this.onboarding});

  final HealthProfile profile;
  final bool onboarding;

  @override
  ConsumerState<_HealthForm> createState() => _HealthFormState();
}

class _HealthFormState extends ConsumerState<_HealthForm> {
  final _form = GlobalKey<FormState>();
  late DiagnosisStatus? _status = widget.profile.diagnosisStatus;
  late DiabetesType? _type = widget.profile.diabetesType;
  late final TextEditingController _year = TextEditingController(
    text: widget.profile.diagnosedYear?.toString() ?? '',
  );
  late final Set<Treatment> _treatments = {...widget.profile.treatments};
  bool _loading = false;
  bool _saved = false;
  String? _error;

  bool get _dirty {
    if (_saved) return false;
    final original = widget.profile;
    return _status != original.diagnosisStatus ||
        _type != original.diabetesType ||
        _year.text.trim() != (original.diagnosedYear?.toString() ?? '') ||
        _treatments.length != original.treatments.length ||
        !_treatments.containsAll(original.treatments);
  }

  @override
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  void _toggleTreatment(Treatment treatment) {
    setState(() {
      if (_treatments.contains(treatment)) {
        _treatments.remove(treatment);
        return;
      }
      if (treatment.isExclusive) {
        _treatments
          ..clear()
          ..add(treatment);
      } else {
        _treatments
          ..removeWhere((item) => item.isExclusive)
          ..add(treatment);
      }
    });
  }

  Future<void> _save() async {
    if (_status == null) {
      setState(
        () => _error =
            'Pilih salah satu status diagnosis. Kamu boleh memilih "Tidak ingin menjawab".',
      );
      return;
    }
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(healthControllerProvider.notifier)
          .save(
            status: _status!,
            type: _type,
            year: int.tryParse(_year.text.trim()),
            treatments: _status == DiagnosisStatus.undisclosed
                ? const []
                : _treatments.toList(),
          );
      if (!mounted) return;
      setState(() => _saved = true);
      if (!widget.onboarding) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Perubahan tersimpan.')));
        context.pop();
      } else {
        final status = ref.read(onboardingControllerProvider).value;
        if (status != null) context.go(routeForOnboarding(status.state));
      }
    } catch (error) {
      if (mounted) setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diagnosed = _status == DiagnosisStatus.diagnosed;
    final askTreatment =
        _status != null && _status != DiagnosisStatus.undisclosed;
    final currentYear = DateTime.now().year;
    return DiscardGuard(
      dirty: _dirty && !widget.onboarding,
      child: PageScaffold(
        title: widget.onboarding ? null : 'Profil Kesehatan',
        showBack: !widget.onboarding,
        bottom: PillButton(
          label: widget.onboarding ? 'Lanjut' : 'Simpan',
          loading: _loading,
          onPressed: _save,
        ),
        children: [
          if (widget.onboarding) ...[
            const StepHeader(current: 3, total: 4),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (widget.onboarding) ...[
            Semantics(
              header: true,
              child: Text(
                'Kenali Kondisi Kesehatanmu',
                style: AppTypography.headline,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (widget.onboarding) ...[
            Text(
              'Informasi ini berdasarkan yang kamu ketahui atau pernah disampaikan oleh tenaga kesehatan.',
              style: AppTypography.secondary,
            ),
            const SizedBox(height: AppSpacing.md),
          ] else
            FormHero.domain(
              DomainStyle.glucose,
              'Dilaporkan sendiri',
              subtitle:
                  'Berdasarkan yang kamu ketahui atau pernah disampaikan tenaga kesehatan. Bukan diagnosis.',
            ),

          Semantics(
            header: true,
            child: Text(
              'Status diagnosis diabetes',
              style: AppTypography.title,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final option in DiagnosisStatus.values) ...[
            SelectionCard(
              title: option.label,
              description: option.description,
              selected: _status == option,
              onTap: () => setState(() {
                _status = option;
                if (option != DiagnosisStatus.diagnosed) {
                  _type = null;
                  _year.clear();
                }
                if (option == DiagnosisStatus.undisclosed) _treatments.clear();
              }),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (diagnosed) ...[
            const SizedBox(height: AppSpacing.md),
            Semantics(
              header: true,
              child: Text('Jenis diabetes', style: AppTypography.title),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final option in DiabetesType.values) ...[
              SelectionCard(
                title: option.label,
                selected: _type == option,
                onTap: () => setState(() => _type = option),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            const SizedBox(height: AppSpacing.sm),
            Form(
              key: _form,
              child: AppTextField(
                label: 'Tahun diagnosis (opsional)',
                hint: 'mis. 2020',
                controller: _year,
                helper: 'Boleh dikosongkan bila kamu tidak ingat.',
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                validator: (value) => validateOptionalYear(
                  value,
                  minYear: 1900,
                  maxYear: currentYear,
                  label: 'Tahun diagnosis',
                ),
              ),
            ),
          ] else
            Form(key: _form, child: const SizedBox.shrink()),
          if (askTreatment) ...[
            const SizedBox(height: AppSpacing.lg),
            Semantics(
              header: true,
              child: Text('Konteks pengobatan', style: AppTypography.title),
            ),
            const SizedBox(height: 2),
            Text(
              'Boleh pilih lebih dari satu. Tanpa dosis atau resep.',
              style: AppTypography.secondary.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final treatment in Treatment.values)
                  PillChip(
                    label: treatment.label,
                    selected: _treatments.contains(treatment),
                    onTap: () => _toggleTreatment(treatment),
                  ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(_error!),
          ],
        ],
      ),
    );
  }
}
