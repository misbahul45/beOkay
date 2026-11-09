/// What the avatar says. Pure and deterministic: every line is built from facts the app already has
/// (time of day, own records today). It never comments on health values.
class AvatarMessage {
  const AvatarMessage(this.title, [this.detail]);
  final String title;
  final String? detail;
}

String firstName(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '' : trimmed.split(RegExp(r'\s+')).first;
}

String partOfDay(int hour) => hour < 11 ? 'pagi' : hour < 15 ? 'siang' : hour < 18 ? 'sore' : 'malam';

/// One short greeting and at most one gentle prompt. Quiet when there is nothing useful to say.
AvatarMessage greetingFor({required DateTime now, required String name, int unconfirmedMedications = 0, bool noMealToday = false}) {
  final who = firstName(name);
  final call = who.isEmpty ? 'Halo!' : 'Halo, $who!';
  final part = partOfDay(now.hour);
  if (unconfirmedMedications > 0) return AvatarMessage('$call Bagaimana kabarmu $part ini?', 'Ada $unconfirmedMedications obat yang belum dikonfirmasi.');
  if (noMealToday && now.hour >= 11 && now.hour < 21) return AvatarMessage('$call Sudah makan ${now.hour < 15 ? 'siang' : now.hour < 18 ? 'sore' : 'malam'}?', 'Catat kalau sudah, supaya ringkasanmu lengkap.');
  return AvatarMessage('$call Bagaimana kabarmu $part ini?');
}
