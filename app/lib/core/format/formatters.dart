import 'package:intl/intl.dart';

String formatDate(DateTime value) =>
    DateFormat('d MMM y', 'id_ID').format(value.toLocal());

String revisionLabel(int version, {bool archived = false}) => [
  if (version > 1) 'Dikoreksi ${version - 1} kali',
  if (archived) 'Diarsipkan',
].join(' · ');

String updatedAtLabel(String? iso) {
  final at = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (at == null) return '';
  final now = DateTime.now();
  final sameDay =
      at.year == now.year && at.month == now.month && at.day == now.day;
  return 'Terakhir diperbarui ${DateFormat(sameDay ? 'HH.mm' : 'd MMM, HH.mm', 'id_ID').format(at)}';
}
