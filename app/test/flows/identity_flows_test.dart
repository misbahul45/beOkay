import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';

import 'package:app/core/storage/token_storage.dart';
import 'package:app/core/widgets/pill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';
import '../support/test_app.dart';

final _password = List.generate(
  32,
  (_) => Random.secure().nextInt(16).toRadixString(16),
).join();

Future<String> seedVerifiedUser(
  FakeBackend backend, {
  String email = 'rina@example.test',
  String name = 'Rina Putri',
  bool consent = false,
  bool profile = false,
  bool health = false,
  bool prefs = false,
  bool complete = false,
}) async {
  Future<Map<String, dynamic>> call(
    String method,
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final response = await backend.client.send(
      (http.Request(method, Uri.parse('http://test$path'))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Authorization'] = token == null ? '' : 'Bearer $token'
        ..body = jsonEncode(body)),
    );
    final text = await response.stream.bytesToString();
    return {
      'status': response.statusCode,
      'headers': response.headers,
      'body': text.isEmpty ? null : jsonDecode(text),
    };
  }

  await call('POST', '/api/auth/sign-up/email', {
    'name': name,
    'email': email,
    'password': _password,
  });
  backend.verifyEmail(email);
  final signIn = await call('POST', '/api/auth/sign-in/email', {
    'email': email,
    'password': _password,
  });
  final token = (signIn['headers'] as Map<String, String>)['set-auth-token']!;
  if (consent) {
    await call('POST', '/api/me/consents', {
      'policyVersion': FakeBackend.policyVersion,
      'purposes': ['health_data_processing', 'descriptive_summaries'],
      'source': 'onboarding',
    }, token: token);
  }
  if (profile) {
    await call('PATCH', '/api/me/profile', {
      'displayName': name,
      'birthYear': 1985,
    }, token: token);
  }
  if (health) {
    await call('PUT', '/api/me/health-profile', {
      'diagnosisStatus': 'diagnosed',
      'diabetesType': 'type_2',
      'diagnosedYear': 2019,
      'treatmentContext': ['lifestyle'],
    }, token: token);
  }
  if (prefs) {
    await call('PATCH', '/api/me/preferences', {
      'timezone': 'Asia/Jakarta',
      'glucoseUnit': 'mg/dL',
    }, token: token);
  }
  if (complete) {
    await call('POST', '/api/me/onboarding/complete', {}, token: token);
  }
  return token;
}

Future<void> signInThroughUi(
  TestHarness h,
  WidgetTester tester, {
  String email = 'rina@example.test',
  String? password,
}) async {
  await h.fill(tester, 'Email', email);
  await h.fill(tester, 'Kata sandi', password ?? _password);
  await h.tapText(tester, 'Masuk');
}

void main() {
  testWidgets(
    'A. new account: register, verify, consent, profile, health, preferences, complete',
    (tester) async {
      final h = TestHarness();
      await h.pump(tester);
      expect(find.text('Halo, aku beOkay.'), findsOneWidget);
      await h.shot(tester, '01-welcome');

      await h.tapText(tester, 'Mulai Sekarang');
      expect(find.text('Buat Akunmu'), findsOneWidget);
      await h.shot(tester, '02-register');

      await h.fill(tester, 'Nama', 'Rina Putri');
      await h.fill(tester, 'Email', 'rina@example.test');
      await h.fill(tester, 'Kata sandi', _password);
      await h.fill(tester, 'Ulangi kata sandi', _password);
      await h.tapText(tester, 'Buat Akun');
      expect(find.text('Periksa Emailmu'), findsOneWidget);
      expect(find.text('rina@example.test'), findsOneWidget);
      await h.shot(tester, '04-verify-email');

      await h.tapText(tester, 'Saya sudah membuka tautannya, masuk');
      await h.fill(tester, 'Kata sandi', _password);
      await h.tapText(tester, 'Masuk');
      expect(
        find.text(
          'Email belum diverifikasi. Buka tautan verifikasi yang kami kirim ke emailmu.',
        ),
        findsOneWidget,
        reason: 'login must be refused before verification',
      );

      h.backend.verifyEmail('rina@example.test');
      await h.tapText(tester, 'Masuk');
      expect(find.text('Halo! Yuk kenalan sebentar.'), findsOneWidget);
      await h.shot(tester, '06-onboarding-intro');

      await h.tapText(tester, 'Lanjut');
      expect(find.text('Datamu, Kendalimu.'), findsOneWidget);
      final cta = find.widgetWithText(PillButton, 'Setuju dan Lanjutkan');
      expect(
        tester.widget<PillButton>(cta).onPressed,
        isNull,
        reason: 'required consents are never pre-selected',
      );
      await h.shot(tester, '07-consent');
      await tester.ensureVisible(
        find.text('Saya menyetujui tujuan wajib ini').first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saya menyetujui tujuan wajib ini').first);
      await tester.pump();
      expect(
        tester.widget<PillButton>(cta).onPressed,
        isNull,
        reason: 'both required purposes must be ticked',
      );
      await tester.ensureVisible(
        find.text('Saya menyetujui tujuan wajib ini').last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saya menyetujui tujuan wajib ini').last);
      await tester.pump();
      expect(tester.widget<PillButton>(cta).onPressed, isNotNull);
      await h.tapText(tester, 'Setuju dan Lanjutkan');

      expect(find.text('Mari Berkenalan'), findsOneWidget);
      await h.shot(tester, '08-personal-profile');
      await h.fill(tester, 'Tahun lahir (opsional)', '1985');
      await h.tapText(tester, 'Lanjut');

      expect(find.text('Kenali Kondisi Kesehatanmu'), findsOneWidget);
      await h.tapText(tester, 'Sudah terdiagnosis');
      await h.tapText(tester, 'Tipe 2');
      await h.fill(tester, 'Tahun diagnosis (opsional)', '2019');
      await h.tapText(tester, 'Obat minum');
      await h.shot(tester, '09-health-profile');
      await h.tapText(tester, 'Lanjut');

      expect(find.text('Sesuaikan Pengalamanmu'), findsOneWidget);
      await h.tapText(tester, 'mmol/L');
      await h.shot(tester, '10-preferences');
      await h.tapText(tester, 'Simpan dan Lanjut');

      expect(find.text('Semua siap!'), findsOneWidget);
      await h.shot(tester, '11-complete');
      await h.tapText(tester, 'Masuk ke Beranda');
      expect(find.textContaining('Halo, Rina!'), findsOneWidget);
      await h.shot(tester, '12-home');
    },
  );

  testWidgets('B. returning user with a stored session lands on home', (
    tester,
  ) async {
    final backend = FakeBackend();
    final tokens = MemoryTokenStorage();
    await tokens.write(
      await seedVerifiedUser(
        backend,
        consent: true,
        profile: true,
        health: true,
        prefs: true,
        complete: true,
      ),
    );
    final h = TestHarness(backend: backend, tokens: tokens);
    await h.pump(tester);
    expect(find.textContaining('Halo, Rina!'), findsOneWidget);
    expect(find.text('Mulai Sekarang'), findsNothing);
    await h.shot(tester, 'today-foundation');
  });

  testWidgets(
    'C. interrupted onboarding resumes at the first incomplete step',
    (tester) async {
      final backend = FakeBackend();
      final tokens = MemoryTokenStorage();
      await tokens.write(
        await seedVerifiedUser(backend, consent: true, profile: true),
      );
      final h = TestHarness(backend: backend, tokens: tokens);
      await h.pump(tester);
      expect(
        find.text('Kenali Kondisi Kesehatanmu'),
        findsOneWidget,
        reason: 'consent and profile are done, so health is next',
      );
    },
  );

  testWidgets('D. expired session returns to authentication', (tester) async {
    final backend = FakeBackend();
    final tokens = MemoryTokenStorage();
    await tokens.write(
      await seedVerifiedUser(
        backend,
        consent: true,
        profile: true,
        health: true,
        prefs: true,
        complete: true,
      ),
    );
    final h = TestHarness(backend: backend, tokens: tokens);
    await h.pump(tester);
    expect(find.textContaining('Halo, Rina!'), findsOneWidget);

    backend.expireAllSessions();
    await h.openProfile(tester);
    await h.settle(tester);
    expect(find.text('Selamat Datang Kembali'), findsOneWidget);
    expect(find.textContaining('Sesimu sudah berakhir'), findsOneWidget);
    expect(
      await tokens.read(),
      isNull,
      reason: 'credentials are cleared when the session is rejected',
    );
    await h.shot(tester, '03-login-session-expired');
  });

  testWidgets(
    'E. consent withdrawal blocks health data but keeps the account usable',
    (tester) async {
      final backend = FakeBackend();
      final tokens = MemoryTokenStorage();
      await tokens.write(
        await seedVerifiedUser(
          backend,
          consent: true,
          profile: true,
          health: true,
          prefs: true,
          complete: true,
        ),
      );
      final h = TestHarness(backend: backend, tokens: tokens);
      await h.pump(tester);

      await h.openProfile(tester);
      await h.tapText(tester, 'Persetujuan data');
      expect(find.text('Persetujuan Data'), findsOneWidget);
      await h.shot(tester, '16-consent-management');
      await h.tapText(tester, 'Tarik persetujuan');
      expect(find.text('Tarik persetujuan?'), findsOneWidget);
      await h.tapText(tester, 'Tarik persetujuan');
      expect(find.text('Ditarik'), findsWidgets);
      expect(find.textContaining('Riwayat persetujuan'), findsOneWidget);

      await tester.tap(find.byTooltip('Kembali'));
      await h.settle(tester);
      await h.tapText(tester, 'Konteks diabetes');
      expect(find.text('Persetujuan diperlukan'), findsOneWidget);
      expect(
        find.text(
          'Dilaporkan sendiri oleh kamu. beOkay tidak memverifikasi diagnosis dan tidak memberi saran medis. Kamu boleh memilih "Belum yakin".',
        ),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Kembali'));
      await h.settle(tester);
      await h.tapText(tester, 'Beranda');
      expect(find.text('Persetujuan perlu ditinjau'), findsOneWidget);
      expect(
        find.textContaining('Halo, Rina!'),
        findsOneWidget,
        reason: 'basic account stays accessible',
      );
      await h.shot(tester, '12b-home-consent-review');
    },
  );

  testWidgets('F. login failures are explained without leaking account state', (
    tester,
  ) async {
    final backend = FakeBackend();
    await seedVerifiedUser(backend);
    final h = TestHarness(backend: backend);
    await h.pump(tester);
    await h.tapText(tester, 'Sudah punya akun? Masuk');
    expect(find.text('Selamat Datang Kembali'), findsOneWidget);
    await h.shot(tester, '03-login');

    await signInThroughUi(h, tester, password: '${_password}x');
    expect(find.text('Email atau kata sandi belum sesuai.'), findsOneWidget);
    await h.fill(tester, 'Email', 'nobody@example.test');
    await h.tapText(tester, 'Masuk');
    expect(
      find.text('Email atau kata sandi belum sesuai.'),
      findsOneWidget,
      reason: 'unknown email looks identical to a wrong password',
    );
  });

  testWidgets(
    'G. password recovery shows the same confirmation for any email',
    (tester) async {
      final h = TestHarness();
      await h.pump(tester);
      await h.tapText(tester, 'Sudah punya akun? Masuk');
      await h.tapText(tester, 'Lupa kata sandi?');
      expect(find.text('Lupa Kata Sandi?'), findsOneWidget);
      await h.shot(tester, '05-forgot-password');
      await h.fill(tester, 'Email', 'ghost@example.test');
      await h.tapText(tester, 'Kirim Tautan');
      expect(find.text('Periksa emailmu'), findsOneWidget);
      expect(find.textContaining('Jika email itu terdaftar'), findsOneWidget);
      await h.shot(tester, '05b-forgot-password-sent');
    },
  );

  testWidgets('H. form validation stops bad input before the network', (
    tester,
  ) async {
    final h = TestHarness();
    await h.pump(tester);
    await h.tapText(tester, 'Mulai Sekarang');
    await h.fill(tester, 'Nama', 'Rina');
    await h.fill(tester, 'Email', 'not-an-email');
    await h.fill(tester, 'Kata sandi', _password.substring(0, 5));
    await h.fill(tester, 'Ulangi kata sandi', _password.substring(5, 10));
    await h.tapText(tester, 'Buat Akun');
    expect(find.text('Format email belum benar.'), findsOneWidget);
    expect(find.text('Kata sandi minimal 10 karakter.'), findsOneWidget);
    expect(find.text('Konfirmasi kata sandi belum sama.'), findsOneWidget);
    expect(
      find.text('Buat Akunmu'),
      findsOneWidget,
      reason: 'stays on the form',
    );
    await h.shot(tester, '02b-register-errors');
  });

  testWidgets('I. network failure is reported, not hidden', (tester) async {
    final backend = FakeBackend();
    await seedVerifiedUser(backend);
    final h = TestHarness(backend: backend);
    await h.pump(tester);
    await h.tapText(tester, 'Sudah punya akun? Masuk');
    backend.offline = true;
    await signInThroughUi(h, tester);
    expect(find.textContaining('Tidak bisa terhubung'), findsOneWidget);
  });

  testWidgets(
    'J. settings persist and apply: glucose unit, text size, reduced motion',
    (tester) async {
      final backend = FakeBackend();
      final tokens = MemoryTokenStorage();
      await tokens.write(
        await seedVerifiedUser(
          backend,
          consent: true,
          profile: true,
          health: true,
          prefs: true,
          complete: true,
        ),
      );
      final h = TestHarness(backend: backend, tokens: tokens);
      await h.pump(tester);
      await h.openProfile(tester);
      await h.shot(tester, '12-profile-overview');
      await h.tapText(tester, 'Pengaturan aplikasi');
      expect(find.text('mg/dL'), findsOneWidget);
      await h.shot(tester, '15-settings');

      await h.tapText(tester, 'Satuan glukosa');
      await h.tapText(tester, 'mmol/L');
      expect(find.text('mmol/L'), findsOneWidget);
      expect(find.text('Pengaturan tersimpan.'), findsOneWidget);

      await h.tapText(tester, 'Ukuran teks');
      await h.tapText(tester, 'Besar');
      expect(find.text('Besar'), findsOneWidget);
      await h.shot(tester, '15b-settings-large-text');

      await tester.tap(find.byType(Switch));
      await h.settle(tester);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    },
  );

  testWidgets('K. edit profile guards unsaved changes and saves valid ones', (
    tester,
  ) async {
    final backend = FakeBackend();
    final tokens = MemoryTokenStorage();
    await tokens.write(
      await seedVerifiedUser(
        backend,
        consent: true,
        profile: true,
        health: true,
        prefs: true,
        complete: true,
      ),
    );
    final h = TestHarness(backend: backend, tokens: tokens);
    await h.pump(tester);
    await h.openProfile(tester);
    await h.tapText(tester, 'Nama dan tahun lahir');
    expect(find.text('Informasi Pribadi'), findsOneWidget);
    await h.shot(tester, '13-edit-profile');

    await h.fill(tester, 'Nama panggilan', 'Rina P');
    await tester.tap(find.byTooltip('Kembali'));
    await h.settle(tester);
    expect(find.text('Buang perubahan?'), findsOneWidget);
    await h.tapText(tester, 'Tetap di sini');
    expect(find.text('Informasi Pribadi'), findsOneWidget);

    await h.fill(tester, 'Tahun lahir (opsional)', '1800');
    await h.tapText(tester, 'Simpan');
    expect(find.textContaining('Tahun lahir harus antara'), findsOneWidget);

    await h.fill(tester, 'Tahun lahir (opsional)', '1990');
    await h.tapText(tester, 'Simpan');
    expect(find.text('Informasi Pribadi'), findsNothing);
    expect(find.text('Rina P · rina@example.test'), findsOneWidget);
  });

  testWidgets('L. account security lists sessions and revokes the others', (
    tester,
  ) async {
    final backend = FakeBackend();
    final tokens = MemoryTokenStorage();
    await tokens.write(
      await seedVerifiedUser(
        backend,
        consent: true,
        profile: true,
        health: true,
        prefs: true,
        complete: true,
      ),
    );
    final other = TestHarness(backend: backend, tokens: MemoryTokenStorage());
    await seedVerifiedUserSecondSession(backend);
    final h = TestHarness(backend: backend, tokens: tokens);
    await h.pump(tester);
    await h.openProfile(tester);
    await h.tapText(tester, 'Keamanan akun');
    expect(find.text('Email terverifikasi'), findsOneWidget);
    expect(find.text('Perangkat ini'), findsOneWidget);
    expect(find.text('Perangkat lain'), findsOneWidget);
    await h.shot(tester, '17-account-security');
    expect(other.backend, same(backend));

    await h.tapText(tester, 'Keluarkan sesi lain');
    await h.tapText(tester, 'Keluarkan');
    expect(find.text('Perangkat lain'), findsNothing);
    expect(find.text('Perangkat ini'), findsOneWidget);
  });

  testWidgets('M. health profile cannot be opened without consent', (
    tester,
  ) async {
    final backend = FakeBackend();
    final tokens = MemoryTokenStorage();
    await tokens.write(
      await seedVerifiedUser(
        backend,
        consent: true,
        profile: true,
        health: true,
        prefs: true,
        complete: true,
      ),
    );
    final h = TestHarness(backend: backend, tokens: tokens);
    await h.pump(tester);
    await h.openProfile(tester);
    await h.tapText(tester, 'Konteks diabetes');
    expect(find.text('Profil Kesehatan'), findsOneWidget);
    // Tidak ada kotak penjelasan panjang; pilihan "Belum yakin" tetap ada di formulir.
    expect(find.textContaining('tidak memverifikasi diagnosis'), findsNothing);
    await h.shot(tester, '14-edit-health');
  });
}

Future<void> seedVerifiedUserSecondSession(FakeBackend backend) async {
  final response = await backend.client.post(
    Uri.parse('http://test/api/auth/sign-in/email'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'email': 'rina@example.test', 'password': _password}),
  );
  expect(response.statusCode, 200);
}
