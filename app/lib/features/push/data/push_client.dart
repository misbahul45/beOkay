import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pembungkus FCM di perangkat. Dipisah agar logika bisa dites tanpa plugin platform.
abstract interface class PushClient {
  /// False bila Firebase tidak terkonfigurasi untuk aplikasi ini (mis. tanpa google-services.json) atau tidak didukung.
  Future<bool> available();

  /// True bila pengguna mengizinkan notifikasi.
  Future<bool> requestPermission();
  Future<String?> token();
  Stream<String> get onTokenRefresh;

  /// Mencabut token di perangkat (dipakai saat pengguna mematikan push atau keluar akun).
  Future<void> deleteToken();

  Stream<Map<String, dynamic>> get onOpened;
  Future<Map<String, dynamic>?> openedAtLaunch();
}

// Catatan: firebase_messaging 17 menandai getToken/onTokenRefresh/deleteToken usang demi register()/onRegistered (FID).
// Server memakai FCM HTTP v1 dengan registration token standar; kecocokan FID dengan `message.token` belum diverifikasi,
// sehingga API token standar dipertahankan sampai diuji dengan aplikasi Firebase yang sudah terdaftar.
// ignore_for_file: deprecated_member_use
class FirebasePushClient implements PushClient {
  bool? _available;

  @override
  Future<bool> available() async {
    if (_available != null) return _available!;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      _available = true;
    } catch (_) {
      _available =
          false; // tanpa konfigurasi Firebase untuk aplikasi ini: push tidak tersedia, bukan galat
    }
    return _available!;
  }

  @override
  Future<bool> requestPermission() async {
    if (!await available()) return false;
    final s = await FirebaseMessaging.instance.requestPermission();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> token() async =>
      await available() ? FirebaseMessaging.instance.getToken() : null;

  @override
  Stream<String> get onTokenRefresh =>
      FirebaseMessaging.instance.onTokenRefresh;

  @override
  Future<void> deleteToken() async {
    if (await available()) await FirebaseMessaging.instance.deleteToken();
  }

  @override
  Stream<Map<String, dynamic>> get onOpened =>
      FirebaseMessaging.onMessageOpenedApp.map((m) => m.data);

  @override
  Future<Map<String, dynamic>?> openedAtLaunch() async {
    if (!await available()) return null;
    return (await FirebaseMessaging.instance.getInitialMessage())?.data;
  }
}

final pushClientProvider = Provider<PushClient>((ref) => FirebasePushClient());
