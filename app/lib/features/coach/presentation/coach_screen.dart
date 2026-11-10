import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ids/record_id.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/beokay_spark.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/tab_root_header.dart';
import '../application/coach_controller.dart';
import '../data/coach_repository.dart';

const _nutrientLabels = {
  'calories': 'Energi (kkal)',
  'carbohydrates': 'Karbohidrat (g)',
  'protein': 'Protein (g)',
  'fat': 'Lemak (g)',
  'fiber': 'Serat (g)',
};

/// Asisten pencari alternatif makanan. Semua saran menunggu persetujuanmu; menawarkan tidak mengubah catatan apa pun.
class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});
  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final input = TextEditingController();

  /// Percakapan: satu atau lebih giliran. Saran dari semua giliran tetap tampil sampai diputuskan.
  final List<CoachRun> runs = [];
  CoachRun? get run => runs.isEmpty ? null : runs.last;
  String? progress;
  bool busy = false;
  Object? error;
  bool consentRequired = false;
  // Satu operationId per niat per saran; dipakai ulang bila pengguna mengulang setelah gagal jaringan.
  final Map<String, String> _ops = {};

  @override
  void initState() {
    super.initState();
    _restore();
  }

  /// Setelah aplikasi dimulai ulang, saran yang masih menunggu di server tampil lagi (server adalah sumber kebenaran).
  Future<void> _restore() async {
    try {
      final pending = await ref.read(coachRepositoryProvider).pendingRuns();
      if (mounted && runs.isEmpty && pending.isNotEmpty) {
        setState(() => runs.addAll(pending));
      }
    } catch (_) {
      // pemulihan bersifat tambahan; kegagalan tidak mengganggu layar
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> ask() async {
    final text = input.text.trim();
    if (text.length < 2) {
      setState(() => error = 'Tulis makanan yang ingin dicari alternatifnya.');
      return;
    }
    await _start(text, previous: null);
  }

  /// Giliran lanjutan pada percakapan yang sama ("pilihan lain", "kenapa").
  Future<void> followUp(String message) => _start(message, previous: run);

  Future<void> _start(String text, {required CoachRun? previous}) async {
    setState(() {
      busy = true;
      error = null;
      consentRequired = false;
      progress = null;
    });
    try {
      final repo = ref.read(coachRepositoryProvider);
      var r = await repo.createRun(
        idempotencyKey: newRecordId(),
        message: text,
        previousRunId: previous?.id,
        background: true,
      );
      if (!r.settled) r = await _follow(repo, r);
      if (mounted) {
        setState(() {
          if (previous == null) runs.clear();
          runs.add(r);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          consentRequired = e is ApiException && e.code == 'CONSENT_REQUIRED';
          error = consentRequired ? null : e;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          progress = null;
        });
      }
    }
  }

  /// Ikuti kemajuan lewat SSE; bila aliran gagal, beralih ke polling sederhana. Hasil akhir selalu dari server.
  Future<CoachRun> _follow(CoachRepository repo, CoachRun started) async {
    try {
      await for (final u in repo.watchRun(started.id)) {
        if (u.run != null) return u.run!;
        final l = u.label;
        if (l != null && mounted) setState(() => progress = l);
      }
    } catch (_) {
      // jatuh ke polling di bawah
    }
    var latest = started;
    for (var i = 0; i < 20 && !latest.settled; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      latest = await repo.getRun(started.id);
    }
    return latest;
  }

  Future<void> decide(Recommendation r, bool accept) async {
    final op = _ops.putIfAbsent('${r.id}:${accept ? 'a' : 'r'}', newRecordId);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(coachRepositoryProvider)
          .decide(r, accept: accept, operationId: op);
      final idx = runs.indexWhere((x) => x.id == r.runId);
      final fresh = await ref
          .read(coachRepositoryProvider)
          .getRun(idx >= 0 ? runs[idx].id : run!.id);
      ref.invalidate(plannedMealsProvider);
      ref.invalidate(activityPlansProvider);
      if (mounted) {
        setState(() => runs[idx >= 0 ? idx : runs.length - 1] = fresh);
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> cancel() async {
    setState(() => busy = true);
    try {
      final r = await ref.read(coachRepositoryProvider).cancel(run!.id);
      if (mounted) setState(() => runs[runs.length - 1] = r);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  SparkState get _sparkState {
    if (busy) {
      return progress == null ? SparkState.thinking : SparkState.searching;
    }
    if (error != null) return SparkState.error;
    if (consentRequired ||
        (run?.consentRequired ?? false) ||
        run?.status == 'BLOCKED') {
      return SparkState.neutral;
    }
    if (run != null && run!.waiting) return SparkState.responding;
    return SparkState.idle;
  }

  @override
  Widget build(BuildContext context) {
    final planned = ref.watch(plannedMealsProvider);
    return PageScaffold(
      showBack: false,
      children: [
        const TabRootHeader(title: 'Asisten'),
        const SizedBox(height: AppSpacing.sm),
        _CompanionHeader(state: _sparkState, progress: progress),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'Tanya asisten',
          hint: 'mis. alternatif pengganti nasi goreng, atau olahraga ringan',
          controller: input,
          maxLength: 200,
          onSubmitted: (_) => ask(),
        ),
        const SizedBox(height: AppSpacing.xs),
        PillButton(
          label: 'Cari pilihan',
          icon: Icons.search_rounded,
          loading: busy,
          onPressed: ask,
        ),
        if (consentRequired) ...[
          const SizedBox(height: AppSpacing.md),
          InfoCard(
            tone: InfoTone.warning,
            title: 'Persetujuan diperlukan',
            text:
                'Aktifkan "Saran personal dari asisten beOkay" di Persetujuan data untuk memakai fitur ini.',
            action: PillButton(
              label: 'Buka persetujuan',
              kind: PillButtonKind.secondary,
              expand: false,
              onPressed: () => context.push(Routes.consentManagement),
            ),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          ErrorBanner(error is String ? error.toString() : messageFor(error!)),
        ],
        if (run != null) ...[
          const SizedBox(height: AppSpacing.md),
          if (run!.consentRequired)
            const InfoCard(
              tone: InfoTone.warning,
              text:
                  'Persetujuan dicabut, jadi saran ini tidak dapat dilanjutkan.',
            )
          else if (run!.message != null && !run!.waiting)
            InfoCard(
              tone: run!.status == 'BLOCKED'
                  ? InfoTone.warning
                  : InfoTone.neutral,
              text: run!.message!,
            ),
          for (final r in runs.expand((x) => x.recommendations)) ...[
            const SizedBox(height: AppSpacing.sm),
            _RecommendationCard(
              rec: r,
              busy: busy,
              onAccept: () => decide(r, true),
              onReject: () => decide(r, false),
            ),
          ],
          if (runs.any((x) => x.recommendations.isNotEmpty) &&
              run!.status != 'BLOCKED') ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: 'Pilihan lain',
                    kind: PillButtonKind.secondary,
                    onPressed: busy
                        ? null
                        : () => followUp('ada pilihan lain?'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PillButton(
                    label: 'Kenapa ini?',
                    kind: PillButtonKind.secondary,
                    onPressed: busy
                        ? null
                        : () => followUp('kenapa ini disarankan?'),
                  ),
                ),
              ],
            ),
          ],
          if (run!.waiting) ...[
            const SizedBox(height: AppSpacing.xs),
            PillButton(
              label: 'Batalkan pencarian',
              kind: PillButtonKind.ghost,
              onPressed: busy ? null : cancel,
            ),
          ],
        ],
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text('Rencana aktivitas', style: AppTypography.title),
        ),
        const SizedBox(height: AppSpacing.xs),
        ref
            .watch(activityPlansProvider)
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              ),
              error: (_, _) => Text(
                'Rencana tidak dapat dimuat.',
                style: AppTypography.secondary,
              ),
              data: (items) => items.isEmpty
                  ? Text(
                      'Belum ada. Rencana bukan catatan aktivitas; catat sesi sebenarnya di Aktivitas.',
                      style: AppTypography.secondary,
                    )
                  : Column(
                      children: [
                        for (final p in items) _ActivityPlanTile(plan: p),
                      ],
                    ),
            ),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text('Rencana makan', style: AppTypography.title),
        ),
        const SizedBox(height: AppSpacing.xs),
        planned.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(),
          ),
          error: (_, _) => Text(
            'Rencana tidak dapat dimuat.',
            style: AppTypography.secondary,
          ),
          data: (items) => items.isEmpty
              ? Text(
                  'Belum ada. Rencana bukan catatan makan; catat konsumsi sebenarnya di Catatan.',
                  style: AppTypography.secondary,
                )
              : Column(
                  children: [for (final p in items) _PlannedTile(meal: p)],
                ),
        ),
      ],
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.rec,
    required this.busy,
    required this.onAccept,
    required this.onReject,
  });
  final Recommendation rec;
  final bool busy;
  final VoidCallback onAccept, onReject;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: AppRadius.cardRadius,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rec.title, style: AppTypography.title),
          const SizedBox(height: 4),
          Text(rec.explanation, style: AppTypography.body),
          if (rec.writtenByModel)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Ditulis dengan bantuan AI.',
                style: AppTypography.caption,
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${rec.isActivity ? 'Aktivitas' : 'Per 100 g'} · data ${rec.dataCoverage == 'COMPLETE'
                ? 'lengkap'
                : rec.dataCoverage == 'PARTIAL'
                ? 'sebagian'
                : 'kosong'}',
            style: AppTypography.caption,
          ),
          if (!rec.isActivity)
            for (final e in _nutrientLabels.entries)
              Text(
                '${e.value}: ${rec.per100g[e.key] ?? 'tidak tersedia'}',
                style: AppTypography.secondary,
              ),
          if (rec.isActivity)
            Text(
              'Durasi: ${rec.activityMinutes} menit',
              style: AppTypography.secondary,
            ),
          const SizedBox(height: AppSpacing.xs),
          Text('Sumber: ${rec.source}', style: AppTypography.caption),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Kenapa ini muncul',
              style: AppTypography.secondaryStrong,
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(rec.rankingReason, style: AppTypography.caption),
              ),
              for (final l in rec.limitations)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $l', style: AppTypography.caption),
                  ),
                ),
            ],
          ),
          if (rec.offered)
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: 'Tolak',
                    kind: PillButtonKind.secondary,
                    onPressed: busy ? null : onReject,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PillButton(
                    label: 'Simpan ke rencana',
                    onPressed: busy ? null : onAccept,
                  ),
                ),
              ],
            )
          else
            StatusBadge(
              label: switch (rec.status) {
                'ACCEPTED' => 'Masuk rencana',
                'REJECTED' => 'Ditolak',
                'EXPIRED' => 'Kedaluwarsa',
                _ => 'Tidak berlaku',
              },
              tone: rec.status == 'ACCEPTED' ? InfoTone.info : InfoTone.neutral,
            ),
        ],
      ),
    ),
  );
}

class _PlannedTile extends ConsumerWidget {
  const _PlannedTile({required this.meal});
  final PlannedMeal meal;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: AppColors.surface,
      borderRadius: AppRadius.cardRadius,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(meal.name, style: AppTypography.bodyStrong),
            Text(
              '${meal.statusLabel} · ${meal.source}',
              style: AppTypography.caption,
            ),
            if (meal.measuredKind != null)
              Text(
                'Terbukti: makanan serupa tercatat di catatan makanmu.',
                style: AppTypography.caption,
              ),
            if (meal.status == 'PLANNED')
              Row(
                children: [
                  TextButton(
                    onPressed: () => _fb(context, ref, true),
                    child: const Text('Sudah dimakan'),
                  ),
                  TextButton(
                    onPressed: () => _fb(context, ref, false),
                    child: const Text('Tidak jadi'),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _fb(BuildContext context, WidgetRef ref, bool consumed) async {
    try {
      await ref
          .read(coachRepositoryProvider)
          .feedback(
            meal.recommendationId,
            consumed: consumed,
            operationId: newRecordId(),
          );
      ref.invalidate(plannedMealsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFor(e))));
      }
    }
  }
}

class _ActivityPlanTile extends ConsumerWidget {
  const _ActivityPlanTile({required this.plan});
  final ActivityPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: AppColors.surface,
      borderRadius: AppRadius.cardRadius,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${plan.label} ${plan.minutes} menit',
              style: AppTypography.bodyStrong,
            ),
            Text(
              '${plan.statusLabel} · ${plan.plannedFor}',
              style: AppTypography.caption,
            ),
            if (plan.measuredKind != null)
              Text(
                'Terbukti: sesi sejenis tercatat di Aktivitas.',
                style: AppTypography.caption,
              ),
            if (plan.status == 'CONFIRMED')
              Row(
                children: [
                  TextButton(
                    onPressed: () => _fb(context, ref, true),
                    child: const Text('Selesai'),
                  ),
                  TextButton(
                    onPressed: () => _fb(context, ref, false),
                    child: const Text('Dilewati'),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _fb(BuildContext context, WidgetRef ref, bool completed) async {
    try {
      await ref
          .read(coachRepositoryProvider)
          .activityFeedback(
            plan.recommendationId,
            completed: completed,
            operationId: newRecordId(),
          );
      ref.invalidate(activityPlansProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFor(e))));
      }
    }
  }
}

class _CompanionHeader extends StatelessWidget {
  const _CompanionHeader({required this.state, this.progress});

  final SparkState state;
  final String? progress;

  ({String title, String detail}) get _copy => switch (state) {
    SparkState.thinking => (
      title: 'Sedang memahami permintaanmu',
      detail: 'Sebentar, ya.',
    ),
    SparkState.searching => (
      title: progress ?? 'Sedang mencari pilihan',
      detail: 'Hanya dari sumber yang tercatat.',
    ),
    SparkState.responding => (
      title: 'Ini pilihan untukmu',
      detail: 'Tidak ada yang tersimpan sampai kamu menyetujuinya.',
    ),
    SparkState.neutral => (
      title: 'Aku tetap di sini',
      detail: 'Baca keterangannya di bawah.',
    ),
    SparkState.error => (
      title: 'Ada kendala',
      detail: 'Catatanmu tidak terpengaruh. Coba lagi sebentar lagi.',
    ),
    _ => (
      title: 'Aku siap membantu',
      detail:
          'Tanya soal pilihan makan atau rencana aktivitas. Semua saran menunggu persetujuanmu.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final copy = _copy;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(AppRadius.hero),
      ),
      child: Row(
        children: [
          BeOkaySpark(size: 64, state: state),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(copy.title, style: AppTypography.title),
                  const SizedBox(height: 2),
                  Text(copy.detail, style: AppTypography.secondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
