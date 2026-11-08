import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/settings_group.dart';
import '../../auth/application/auth_controller.dart';
import '../../health_profile/application/health_controller.dart';
import '../../preferences/application/preferences_controller.dart';
import '../../preferences/presentation/timezone_picker.dart';
import '../application/profile_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final profile = ref.watch(profileControllerProvider).value;
    final health = ref.watch(healthControllerProvider);
    final preferences = ref.watch(effectivePreferencesProvider);
    final name = auth is AuthAuthenticated ? auth.user.name : '';
    final email = auth is AuthAuthenticated ? auth.user.email : '';
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final healthValue = health.when(
      data: (value) => (value?.exists ?? false) ? 'Terisi' : 'Belum diisi',
      loading: () => 'Memuat',
      error: (_, _) => 'Perlu persetujuan',
    );
    return PageScaffold(
      showBack: false,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text('Profil', style: AppTypography.headline),
              ),
            ),
            ExcludeSemantics(
              child: Container(
                height: 44,
                width: 44,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(initial, style: AppTypography.title),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          name.isEmpty ? email : '$name · $email',
          style: AppTypography.secondary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.sm + 2),
        SettingsGroup(
          title: 'Informasi pribadi',
          children: [
            SettingsRow(
              icon: Icons.badge_outlined,
              title: 'Nama dan tahun lahir',
              value: profile?.birthYear == null
                  ? 'Tahun lahir belum diisi'
                  : 'Lahir ${profile!.birthYear}',
              onTap: () => context.push(Routes.editProfile),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm + 2),
        SettingsGroup(
          title: 'Profil kesehatan',
          children: [
            SettingsRow(
              icon: Icons.monitor_heart_outlined,
              title: 'Konteks diabetes',
              subtitle: 'Dilaporkan sendiri',
              value: healthValue,
              onTap: () => context.push(Routes.editHealth),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm + 2),
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
              onTap: () => context.push(Routes.settings),
            ),
            SettingsRow(
              icon: Icons.bloodtype_outlined,
              title: 'Satuan glukosa',
              value: preferences.glucoseUnit.label,
              onTap: () => context.push(Routes.settings),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm + 2),
        SettingsGroup(
          title: 'Keamanan & privasi',
          children: [
            SettingsRow(
              icon: Icons.lock_outline,
              title: 'Keamanan akun',
              onTap: () => context.push(Routes.accountSecurity),
            ),
            SettingsRow(
              icon: Icons.verified_user_outlined,
              title: 'Persetujuan data',
              onTap: () => context.push(Routes.consentManagement),
            ),
            SettingsRow(
              icon: Icons.tune,
              title: 'Pengaturan aplikasi',
              onTap: () => context.push(Routes.settings),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const InfoCard(
          text: 'beOkay bukan alat diagnosis dan tidak memberi saran medis.',
          tone: InfoTone.neutral,
        ),
      ],
    );
  }
}
