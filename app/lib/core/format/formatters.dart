import 'package:intl/intl.dart';

String formatDate(DateTime value) =>
    DateFormat('d MMM y', 'id_ID').format(value.toLocal());
