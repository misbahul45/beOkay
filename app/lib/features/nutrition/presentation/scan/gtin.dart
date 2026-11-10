/// Validasi GTIN-8/12/13/14 dengan digit pemeriksa (sama dengan server); mencegah kode salah ketik dikirim.
bool validGtin(String code) {
  if (!RegExp(r'^\d+$').hasMatch(code) ||
      ![8, 12, 13, 14].contains(code.length)) {
    return false;
  }
  final digits = code.split('').map(int.parse).toList();
  final check = digits.removeLast();
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    final fromRight = digits.length - 1 - i;
    sum += digits[i] * (fromRight.isEven ? 3 : 1);
  }
  return (10 - sum % 10) % 10 == check;
}
