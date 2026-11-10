import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/option_sheet.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/settings_group.dart';
import '../../auth/application/auth_controller.dart';
import '../../preferences/application/preferences_controller.dart';
import '../../preferences/data/preferences_models.dart';
import '../../preferences/presentation/timezone_picker.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _save(
    BuildContext context,
    WidgetRef ref, {
    String? timezone,
    GlucoseUnit? glucoseUnit,
    TextSizePreference? textSize,
    bool? reduceMotion,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(preferencesControllerProvider.notifier)
          .save(
            timezone: timezone,
            glucoseUnit: glucoseUnit,
            textSize: textSize,
            reduceMotion: reduceMotion,
          );
      messenger.showSnackBar(
        const SnackBar(content: Text('Pengaturan tersimpan.')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(messageFor(error))));
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        content: const Text('Kamu perlu masuk lagi untuk membuka aplikasi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(effectivePreferencesProvider);
    return PageScaffold(
      title: 'Pengaturan',
      children: [
        SettingsGroup(
          title: 'Preferensi',
          children: [
            const SettingsRow(
              icon: Icons.language,
              title: 'Bahasa',
              value: 'Bahasa Indonesia',
            ),
            SettingsRow(
              icon: Icons.schedule,
              title: 'Zona waktu',
              value: timezoneLabel(preferences.timezone),
              onTap: () async {
                final picked = await showTimezonePicker(
                  context,
                  current: preferences.timezone,
                );
                if (picked != null &&
                    picked != preferences.timezone &&
                    context.mounted) {
                  await _save(context, ref, timezone: picked);
                }
              },
            ),
            SettingsRow(
              icon: Icons.bloodtype_outlined,
              title: 'Satuan glukosa',
              subtitle: 'Hanya mengubah tampilan',
              value: preferences.glucoseUnit.label,
              onTap: () async {
                final picked = await showOptionSheet<GlucoseUnit>(
                  context,
                  title: 'Satuan Glukosa',
                  current: preferences.glucoseUnit,
                  options: [
                    for (final unit in GlucoseUnit.values)
                      (unit, unit.label, null),
                  ],
                );
                if (picked != null &&
                    picked != preferences.glucoseUnit &&
                    context.mounted) {
                  await _save(context, ref, glucoseUnit: picked);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SettingsGroup(
          title: 'Tampilan & aksesibilitas',
          children: [
            SettingsRow(
              icon: Icons.format_size,
              title: 'Ukuran teks',
              value: preferences.textSize.label,
              onTap: () async {
                final picked = await showOptionSheet<TextSizePreference>(
                  context,
                  title: 'Ukuran Teks',
                  current: preferences.textSize,
                  options: [
                    for (final size in TextSizePreference.values)
                      (size, size.label, null),
                  ],
                );
                if (picked != null &&
                    picked != preferences.textSize &&
                    context.mounted) {
                  await _save(context, ref, textSize: picked);
                }
              },
            ),
            SettingsRow(
              icon: Icons.animation,
              title: 'Kurangi gerak',
              subtitle: 'Matikan transisi dan animasi',
              trailing: Switch(
                value: preferences.reduceMotion,
                onChanged: (value) => _save(context, ref, reduceMotion: value),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SettingsGroup(
          title: 'Privasi & keamanan',
          children: [
            SettingsRow(
              icon: Icons.verified_user_outlined,
              title: 'Persetujuan data',
              onTap: () => context.push(Routes.consentManagement),
            ),
            SettingsRow(
              icon: Icons.lock_outline,
              title: 'Keamanan akun',
              onTap: () => context.push(Routes.accountSecurity),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SettingsGroup(
          children: [
            SettingsRow(
              icon: Icons.logout,
              title: 'Keluar',
              destructive: true,
              onTap: () => _signOut(context, ref),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: Text(
            'beOkay · versi 1.0.0',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
