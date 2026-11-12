import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/settings_group.dart';
import '../../auth/application/auth_controller.dart';
import '../../health_profile/application/health_controller.dart';
import '../../health_profile/data/health_models.dart';
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
    final appSummary = [
      'Bahasa Indonesia',
      timezoneLabel(preferences.timezone),
      preferences.glucoseUnit.label,
    ].join(' · ');
    return PageScaffold(
      showBack: false,
      children: [
        Semantics(
          header: true,
          child: Text('Profil', style: AppTypography.headline),
        ),
        const SizedBox(height: AppSpacing.sm),
        _IdentityCard(
          name: name,
          email: email,
          birthYear: profile?.birthYear,
          onEdit: () => context.push(Routes.editProfile),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _SectionTitle('Profil kesehatan'),
        _HealthCard(
          health: health,
          onTap: () => context.push(Routes.editHealth),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _SectionTitle('Rutinitas'),
        _RoutineGrid(
          tiles: [
            _RoutineTile(
              icon: Icons.flag_outlined,
              title: 'Tujuan personal',
              caption: 'Target yang kamu pilih',
              tint: AppColors.goalTint,
              ink: AppColors.goalInk,
              onTap: () => context.push(Routes.goals),
            ),
            _RoutineTile(
              icon: Icons.medication_outlined,
              title: 'Obat dan jadwal',
              caption: 'Jadwal dan riwayat minum',
              tint: AppColors.medicationTint,
              ink: AppColors.medicationInk,
              onTap: () => context.push(Routes.medications),
            ),
            _RoutineTile(
              icon: Icons.notifications_none_rounded,
              title: 'Pengingat',
              caption: 'Kapan kamu diingatkan',
              tint: AppColors.glucoseTint,
              ink: AppColors.glucoseInk,
              onTap: () => context.push(Routes.reminders),
            ),
            _RoutineTile(
              icon: Icons.monitor_heart_outlined,
              title: 'Ukuran & hasil lab',
              caption: 'Berat, tensi, HbA1c',
              tint: AppColors.mealTint,
              ink: AppColors.mealInk,
              onTap: () => context.push(Routes.clinical),
            ),
            _RoutineTile(
              icon: Icons.groups_outlined,
              title: 'Komunitas',
              caption: 'Alias dan tantangan',
              tint: AppColors.activityTint,
              ink: AppColors.activityInk,
              onTap: () => context.push(Routes.community),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SettingsGroup(
          title: 'Asisten & personalisasi',
          children: [
            SettingsRow(
              icon: Icons.auto_awesome_outlined,
              title: 'Asisten beOkay',
              subtitle: 'Alternatif makanan dan rencana aktivitas',
              onTap: () => context.go(Routes.coach),
            ),
            SettingsRow(
              icon: Icons.event_available_outlined,
              title: 'Rencana kecil & refleksi',
              subtitle: 'Langkah dari catatanmu dan refleksi mingguan',
              onTap: () => context.push(Routes.coaching),
            ),
            SettingsRow(
              icon: Icons.psychology_alt_outlined,
              title: 'Memori & personalisasi',
              subtitle: 'Yang diingat asisten, bisa dijeda dan dihapus',
              onTap: () => context.push(Routes.memory),
            ),
            SettingsRow(
              icon: Icons.no_food_outlined,
              title: 'Alergi dan preferensi makanan',
              subtitle: 'Dipakai saat menyarankan makanan',
              onTap: () => context.push(Routes.foodPreferences),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SettingsGroup(
          title: 'Data & keamanan',
          children: [
            SettingsRow(
              icon: Icons.verified_user_outlined,
              title: 'Persetujuan data',
              subtitle: 'Atur data yang boleh diproses',
              onTap: () => context.push(Routes.consentManagement),
            ),
            SettingsRow(
              icon: Icons.lock_outline,
              title: 'Keamanan akun',
              subtitle: 'Kata sandi dan sesi aktif',
              onTap: () => context.push(Routes.accountSecurity),
            ),
            SettingsRow(
              icon: Icons.sync_rounded,
              title: 'Sinkronisasi',
              subtitle: 'Status data di perangkat ini',
              onTap: () => context.push(Routes.sync),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SettingsGroup(
          title: 'Aplikasi',
          children: [
            SettingsRow(
              icon: Icons.notifications_none_rounded,
              title: 'Notifikasi',
              subtitle: 'Kotak masuk, jenis notifikasi, dan push',
              onTap: () => context.push(Routes.notifications),
            ),
            SettingsRow(
              icon: Icons.tune,
              title: 'Pengaturan aplikasi',
              subtitle: appSummary,
              onTap: () => context.push(Routes.settings),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: Text(
            'beOkay bukan alat diagnosis dan tidak memberi saran medis.',
            style: AppTypography.caption,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.xs),
    child: Semantics(
      header: true,
      child: Text(text.toUpperCase(), style: AppTypography.overline),
    ),
  );
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.name,
    required this.email,
    required this.birthYear,
    required this.onEdit,
  });

  final String name;
  final String email;
  final int? birthYear;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final birth = birthYear == null
        ? 'Tahun lahir belum diisi'
        : 'Lahir $birthYear';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.brandTint,
        borderRadius: BorderRadius.circular(AppRadius.hero),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  height: 64,
                  width: 64,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initial,
                    style: AppTypography.heading.copyWith(
                      color: AppColors.brand,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? email : name,
                      style: AppTypography.title.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (name.isNotEmpty)
                      Text(
                        email,
                        style: AppTypography.secondary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: AppSpacing.xs),
                    _Tag(label: birth, onBrandTint: true),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          PillButton(
            label: 'Ubah profil',
            icon: Icons.edit_outlined,
            kind: PillButtonKind.light,
            expand: false,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.onBrandTint = false});

  final String label;
  final bool onBrandTint;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: onBrandTint ? AppColors.surface : AppColors.surfaceMuted,
      borderRadius: AppRadius.pillRadius,
    ),
    child: Text(
      label,
      style: onBrandTint
          ? AppTypography.caption.copyWith(
              color: AppColors.brand,
              fontWeight: FontWeight.w600,
            )
          : AppTypography.caption.copyWith(color: AppColors.textPrimary),
    ),
  );
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.health, required this.onTap});

  final AsyncValue<HealthProfile?> health;
  final VoidCallback onTap;

  static String summary(HealthProfile p) => [
    ?p.diagnosisStatus?.label,
    if (p.diagnosisStatus == DiagnosisStatus.diagnosed &&
        p.diabetesType != null &&
        p.diabetesType != DiabetesType.unknown)
      p.diabetesType!.label,
    if (p.diagnosedYear != null) 'sejak ${p.diagnosedYear}',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final value = health.value;
    final filled = value?.exists ?? false;
    final needsConsent =
        health.error is ApiException &&
        (health.error as ApiException).code == 'CONSENT_REQUIRED';
    final status = health.isLoading && value == null
        ? 'Memuat…'
        : health.hasError
        ? (needsConsent
              ? 'Perlu persetujuan data kesehatan'
              : 'Belum bisa dimuat')
        : filled
        ? summary(value!)
        : 'Belum diisi. Lengkapi agar saran lebih sesuai.';
    final treatments = filled
        ? value!.treatments
              .where((t) => t != Treatment.undisclosed)
              .map((t) => t.label)
              .toList()
        : const <String>[];
    return Semantics(
      button: true,
      label: [
        'Konteks diabetes',
        status,
        ...treatments,
        'Dilaporkan sendiri',
      ].join('. '),
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _IconBubble(
                      icon: Icons.monitor_heart_outlined,
                      tint: AppColors.glucoseTint,
                      ink: AppColors.glucoseInk,
                      size: 40,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Konteks diabetes',
                            style: AppTypography.bodyStrong,
                          ),
                          Text(status, style: AppTypography.secondary),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
                if (treatments.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs - 2,
                    runSpacing: AppSpacing.xs - 2,
                    children: [for (final t in treatments) _Tag(label: t)],
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Dilaporkan sendiri · dipakai untuk menyesuaikan saran, bukan diagnosis',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  const _IconBubble({
    required this.icon,
    required this.tint,
    required this.ink,
    this.size = 36,
  });

  final IconData icon;
  final Color tint;
  final Color ink;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    height: size,
    width: size,
    decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: Icon(icon, size: size * 0.5, color: ink),
  );
}

class _RoutineTile {
  const _RoutineTile({
    required this.icon,
    required this.title,
    required this.caption,
    required this.tint,
    required this.ink,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String caption;
  final Color tint;
  final Color ink;
  final VoidCallback onTap;
}

class _RoutineGrid extends StatelessWidget {
  const _RoutineGrid({required this.tiles});

  final List<_RoutineTile> tiles;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.textScalerOf(context).scale(14) <= 18;
    if (!wide) {
      return Column(
        children: [
          for (final (i, t) in tiles.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpacing.xs + 2),
            _TileCard(tile: t, horizontal: true),
          ],
        ],
      );
    }
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: AppSpacing.xs + 2));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _TileCard(tile: tiles[i])),
              const SizedBox(width: AppSpacing.xs + 2),
              Expanded(
                child: i + 1 < tiles.length
                    ? _TileCard(tile: tiles[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _TileCard extends StatelessWidget {
  const _TileCard({required this.tile, this.horizontal = false});

  final _RoutineTile tile;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final bubble = _IconBubble(icon: tile.icon, tint: tile.tint, ink: tile.ink);
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tile.title,
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(tile.caption, style: AppTypography.caption),
      ],
    );
    return Semantics(
      button: true,
      label: '${tile.title}. ${tile.caption}',
      excludeSemantics: true,
      onTap: tile.onTap,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tile.onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: horizontal
                ? Row(
                    children: [
                      bubble,
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: texts),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bubble,
                      const SizedBox(height: AppSpacing.xs),
                      texts,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
