import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/usage_tracker.dart';
import '../../../core/ids/record_id.dart';
import '../../../core/network/account_scoped_repository.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/notifications/reminder_scheduler.dart';
import 'medication_controller.dart';

Future<String> confirmMedicationFromNotification(
  WidgetRef ref,
  MedicationRef m,
) async {
  try {
    await ref.read(medicationRepositoryProvider).createIntake(m.regimenId, {
      'id': newRecordId(),
      'scheduleId': m.scheduleId,
      'scheduledAt': m.scheduledAt,
      'status': 'taken',
      'takenAt': DateTime.now().toUtc().toIso8601String(),
      'notes': null,
    });
    ref
        .read(usageTrackerProvider)
        .track(
          'notification_opened',
          domain: 'medication',
          meta: {'via': 'notification', 'kind': 'med_taken'},
        );
    return 'Obat tercatat sudah diminum.';
  } on QueuedOffline {
    return 'Tersimpan di perangkat. Akan dikirim saat tersambung.';
  } on ApiException catch (e) {
    if (e.status == 409) return 'Jadwal ini sudah tercatat sebelumnya.';
    return 'Belum tersimpan. Buka halaman Obat untuk mencatat.';
  }
}
