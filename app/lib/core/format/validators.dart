final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

String? validateName(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Nama wajib diisi.';
  if (text.length > 80) return 'Nama maksimal 80 karakter.';
  return null;
}

String? validateEmail(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Email wajib diisi.';
  if (!_emailPattern.hasMatch(text)) return 'Format email belum benar.';
  return null;
}

String? validateNewPassword(String? value) {
  final text = value ?? '';
  if (text.length < 10) return 'Kata sandi minimal 10 karakter.';
  if (text.length > 128) return 'Kata sandi maksimal 128 karakter.';
  return null;
}

String? validateRequired(String? value, String message) => (value == null || value.isEmpty) ? message : null;

String? validateOptionalYear(String? value, {required int minYear, required int maxYear, required String label}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final year = int.tryParse(text);
  if (year == null || year < minYear || year > maxYear) return '$label harus antara $minYear dan $maxYear.';
  return null;
}
