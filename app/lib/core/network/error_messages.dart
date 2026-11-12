import 'account_scoped_repository.dart';
import 'api_exception.dart';

const queuedOfflineMessage =
    'Tersimpan di perangkat. Akan dikirim saat tersambung.';

String messageFor(Object error) {
  if (error is QueuedOffline) return queuedOfflineMessage;
  if (error is! ApiException) return 'Terjadi kendala. Coba lagi.';
  if (error.isNetwork) return error.message;
  if (error.isRateLimited) {
    return 'Terlalu banyak percobaan. Tunggu sebentar lalu coba lagi.';
  }
  switch (error.code) {
    case 'INVALID_EMAIL_OR_PASSWORD':
      return 'Email atau kata sandi belum sesuai.';
    case 'EMAIL_NOT_VERIFIED':
      return 'Email belum diverifikasi. Buka tautan verifikasi yang kami kirim ke emailmu.';
    case 'PASSWORD_TOO_SHORT':
      return 'Kata sandi minimal 10 karakter.';
    case 'PASSWORD_TOO_LONG':
      return 'Kata sandi terlalu panjang.';
    case 'INVALID_PASSWORD':
      return 'Kata sandi saat ini belum sesuai.';
    case 'VALIDATION_ERROR':
      return 'Ada isian yang belum valid. Periksa lagi lalu coba kembali.';
    case 'CONSENT_REQUIRED':
      return 'Persetujuan yang diperlukan belum diberikan.';
    case 'POLICY_VERSION_MISMATCH':
      return 'Kebijakan privasi sudah diperbarui. Muat ulang lalu coba lagi.';
    case 'DETAILS_REQUIRE_DIAGNOSIS':
      return 'Tipe dan tahun diagnosis hanya diisi bila statusnya terdiagnosis.';
    case 'DIAGNOSIS_BEFORE_BIRTH':
      return 'Tahun diagnosis tidak boleh sebelum tahun lahir.';
    case 'VERSION_CONFLICT':
      return 'Data berubah di tempat lain. Muat ulang lalu coba lagi.';
    case 'UNAUTHENTICATED':
      return 'Sesimu sudah berakhir. Masuk kembali.';
    case 'FEATURE_DISABLED':
      return 'Fitur ini dimatikan sementara. Fitur lain tetap bisa dipakai.';
    case 'REPORT_RATE_LIMITED':
      return 'Kamu sudah mengirim beberapa laporan dalam satu jam. Coba lagi nanti.';
    case 'UNIT_NOT_ALLOWED':
      return 'Satuan ini tidak bisa dipakai untuk jenis pengukuran tersebut.';
    case 'VALUE_OUT_OF_RANGE':
      return 'Nilai di luar batas yang bisa dicatat. Periksa lagi angkanya.';
    case 'SYSTOLIC_NOT_ABOVE_DIASTOLIC':
      return 'Angka atas (sistolik) harus lebih besar dari angka bawah (diastolik).';
    case 'STRATEGY_NOT_OFFERED':
      return 'Strategi itu sudah tidak tersedia. Muat ulang refleksi.';
  }
  if (error.status >= 500) return 'Terjadi kendala. Coba lagi nanti.';
  return error.message;
}
