import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/validators.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/discard_guard.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/step_header.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../application/profile_controller.dart';
import '../data/profile_models.dart';

class PersonalProfileScreen extends ConsumerWidget {
  const PersonalProfileScreen({super.key, required this.onboarding});

  final bool onboarding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileControllerProvider);
    final loaded = profile.value;
    if (loaded != null) {
      return _ProfileForm(profile: loaded, onboarding: onboarding);
    }
    return PageScaffold(
      title: onboarding ? null : 'Informasi Pribadi',
      showBack: !onboarding,
      children: [
        AsyncBody<Profile?>(
          value: profile,
          onRetry: () => ref.invalidate(profileControllerProvider),
          data: (_) => const SkeletonList(),
        ),
      ],
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.profile, required this.onboarding});

  final Profile profile;
  final bool onboarding;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.profile.displayName,
  );
  late final TextEditingController _birthYear = TextEditingController(
    text: widget.profile.birthYear?.toString() ?? '',
  );
  bool _loading = false;
  bool _saved = false;
  String? _error;

  bool get _dirty =>
      !_saved &&
      (_name.text.trim() != widget.profile.displayName ||
          _birthYear.text.trim() !=
              (widget.profile.birthYear?.toString() ?? ''));

  @override
  void dispose() {
    _name.dispose();
    _birthYear.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final year = int.tryParse(_birthYear.text.trim());
    try {
      await ref
          .read(profileControllerProvider.notifier)
          .save(
            displayName: _name.text.trim(),
            birthYear: year,
            clearBirthYear: year == null && widget.profile.birthYear != null,
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
    final currentYear = DateTime.now().year;
    return DiscardGuard(
      dirty: _dirty && !widget.onboarding,
      child: PageScaffold(
        title: widget.onboarding ? null : 'Informasi Pribadi',
        showBack: !widget.onboarding,
        bottom: PillButton(
          label: widget.onboarding ? 'Lanjut' : 'Simpan',
          loading: _loading,
          onPressed: _save,
        ),
        children: [
          if (widget.onboarding) ...[
            const StepHeader(current: 2, total: 4),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (widget.onboarding) ...[
            Semantics(
              header: true,
              child: Text('Mari Berkenalan', style: AppTypography.headline),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text(
            'Beberapa informasi dasar membantu menyesuaikan pengalaman aplikasi.',
            style: AppTypography.secondary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Form(
            key: _form,
            child: Column(
              children: [
                AppTextField(
                  label: 'Nama panggilan',
                  hint: 'mis. Rina',
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.nickname],
                  onChanged: (_) => setState(() {}),
                  validator: validateName,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Tahun lahir (opsional)',
                  hint: 'mis. 1985',
                  controller: _birthYear,
                  helper:
                      'Boleh dikosongkan. Dipakai untuk menyesuaikan pengalaman.',
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _save(),
                  validator: (value) => validateOptionalYear(
                    value,
                    minYear: currentYear - 120,
                    maxYear: currentYear,
                    label: 'Tahun lahir',
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(_error!),
          ],
        ],
      ),
    );
  }
}
