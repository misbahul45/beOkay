import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeBackend {
  FakeBackend() {
    client = MockClient(_handle);
  }

  late final MockClient client;

  final Map<String, _User> _users = {};
  final Map<String, String> _tokens = {};
  final List<Map<String, dynamic>> _consents = [];
  final List<String> sentEmails = [];
  int _counter = 0;
  int signInAttempts = 0;
  bool offline = false;

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _health;
  Map<String, dynamic>? _prefs;
  DateTime? _introSeenAt;
  DateTime? _completedAt;
  int _version = 0;

  static const policyVersion = '1.0';

  void verifyEmail(String email) => _users[email.toLowerCase()]?.verified = true;

  void expireAllSessions() => _tokens.clear();

  String? get lastUserId => _users.values.isEmpty ? null : _users.values.last.id;

  http.Response _json(Object? body, {int status = 200, Map<String, String> headers = const {}}) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json', ...headers});

  http.Response _appError(int status, String code, String message, {Map<String, dynamic>? details}) =>
      _json({'error': {'code': code, 'message': message, 'requestId': 'test', 'details': ?details}}, status: status);

  http.Response _authError(int status, String code, String message) => _json({'message': message, 'code': code}, status: status);

  _User? _userFor(http.Request request) {
    final header = request.headers['Authorization'];
    if (header == null || !header.startsWith('Bearer ')) return null;
    final id = _tokens[header.substring(7)];
    if (id == null) return null;
    return _users.values.firstWhere((user) => user.id == id);
  }

  Map<String, dynamic> _userJson(_User user) => {'id': user.id, 'email': user.email, 'name': user.name, 'emailVerified': user.verified};

  List<Map<String, dynamic>> get _purposes => [
        {
          'purpose': 'health_data_processing',
          'required': true,
          'title': 'Mencatat data kesehatan yang kamu masukkan',
          'description': 'Menyimpan profil kesehatan dan catatan harian.',
          'dataCategories': ['Profil kesehatan yang kamu laporkan'],
          'withdrawalEffect': 'Fitur yang memproses data kesehatan dihentikan.',
        },
        {
          'purpose': 'descriptive_summaries',
          'required': true,
          'title': 'Membuat ringkasan dan insight deskriptif',
          'description': 'Menghitung ringkasan dari catatanmu.',
          'dataCategories': ['Ringkasan yang dihitung dari catatanmu'],
          'withdrawalEffect': 'Ringkasan baru tidak dibuat.',
        },
        {
          'purpose': 'product_analytics',
          'required': false,
          'title': 'Membantu meningkatkan aplikasi',
          'description': 'Data penggunaan tanpa isi catatan kesehatan.',
          'dataCategories': ['Data penggunaan aplikasi'],
          'withdrawalEffect': 'Tidak memengaruhi fitur lain.',
        },
      ];

  bool _active(String userId, String purpose) =>
      _consents.any((c) => c['userId'] == userId && c['purpose'] == purpose && c['withdrawnAt'] == null && c['policyVersion'] == policyVersion);

  Map<String, dynamic> _consentOverview(String userId) {
    final mine = _consents.where((c) => c['userId'] == userId).toList().reversed.toList();
    return {
      'policyVersion': policyVersion,
      'purposes': [
        for (final purpose in _purposes)
          () {
            final records = mine.where((c) => c['purpose'] == purpose['purpose']).toList();
            final active = records.where((c) => c['withdrawnAt'] == null).firstOrNull;
            final latest = records.firstOrNull;
            final status = active != null ? 'granted' : (latest != null ? 'withdrawn' : 'not_given');
            final shown = active ?? latest;
            return {
              'purpose': purpose['purpose'],
              'required': purpose['required'],
              'status': status,
              'policyVersion': shown?['policyVersion'],
              'grantedAt': shown?['grantedAt'],
              'withdrawnAt': shown?['withdrawnAt'],
            };
          }(),
      ],
      'history': [
        for (final c in mine)
          {'id': c['id'], 'purpose': c['purpose'], 'policyVersion': c['policyVersion'], 'status': c['withdrawnAt'] == null ? 'granted' : 'withdrawn', 'grantedAt': c['grantedAt'], 'withdrawnAt': c['withdrawnAt'], 'source': c['source']},
      ],
    };
  }

  Map<String, dynamic> _onboarding(_User user) {
    final consentOk = _active(user.id, 'health_data_processing') && _active(user.id, 'descriptive_summaries');
    final steps = {'consent': consentOk, 'personal_profile': _profile != null, 'health_profile': _health != null, 'preferences': _prefs != null};
    final missing = steps.entries.where((e) => !e.value).map((e) => e.key).toList();
    String state;
    if (_completedAt != null) {
      state = 'COMPLETED';
    } else if (!user.verified) {
      state = 'EMAIL_VERIFICATION_PENDING';
    } else if (missing.length == 4 && _introSeenAt == null) {
      state = 'NOT_STARTED';
    } else if (missing.isEmpty) {
      state = 'READY_TO_COMPLETE';
    } else {
      state = {'consent': 'CONSENT_PENDING', 'personal_profile': 'PERSONAL_PROFILE_PENDING', 'health_profile': 'HEALTH_PROFILE_PENDING', 'preferences': 'PREFERENCES_PENDING'}[missing.first]!;
    }
    return {
      'state': state,
      'emailVerified': user.verified,
      'steps': [for (final e in steps.entries) {'key': e.key, 'done': e.value}],
      'introSeenAt': _introSeenAt?.toIso8601String(),
      'completedAt': _completedAt?.toIso8601String(),
      'version': _version,
      'requiresConsentReview': _completedAt != null && !consentOk,
    };
  }

  Map<String, dynamic> _profileJson(_User user) => {
        'exists': _profile != null,
        'displayName': user.name,
        'birthYear': _profile?['birthYear'],
        'completeness': {'complete': _profile?['birthYear'] != null, 'missing': _profile?['birthYear'] == null ? ['birthYear'] : []},
        'createdAt': null,
        'updatedAt': null,
      };

  Map<String, dynamic> _healthJson() => {
        'exists': _health != null,
        'diagnosisStatus': _health?['diagnosisStatus'],
        'diabetesType': _health?['diabetesType'],
        'diagnosedYear': _health?['diagnosedYear'],
        'treatmentContext': _health?['treatmentContext'] ?? [],
        'provenance': {'source': 'user_reported', 'clinicallyVerified': false},
        'eligibilityStatus': 'unknown',
      };

  Map<String, dynamic> _prefsJson() => {
        'locale': 'id-ID',
        'timezone': _prefs?['timezone'] ?? 'Asia/Jakarta',
        'glucoseUnit': _prefs?['glucoseUnit'] ?? 'mg/dL',
        'textSize': _prefs?['textSize'] ?? 'system',
        'reduceMotion': _prefs?['reduceMotion'] ?? false,
        'isDefault': _prefs == null,
        'updatedAt': null,
      };

  Future<http.Response> _handle(http.Request request) async {
    if (offline) throw http.ClientException('offline');
    final path = request.url.path;
    final key = '${request.method} $path';
    final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;

    switch (key) {
      case 'POST /api/auth/sign-up/email':
        final email = (body['email'] as String).toLowerCase();
        if (!_users.containsKey(email)) {
          _users[email] = _User('u${++_counter}', email, body['name'] as String, body['password'] as String);
          sentEmails.add('verify:$email');
        }
        return _json({'token': null, 'user': _userJson(_users[email]!)});
      case 'POST /api/auth/sign-in/email':
        signInAttempts++;
        final user = _users[(body['email'] as String).toLowerCase()];
        if (user == null || user.password != body['password']) return _authError(401, 'INVALID_EMAIL_OR_PASSWORD', 'Invalid email or password');
        if (!user.verified) return _authError(403, 'EMAIL_NOT_VERIFIED', 'Email not verified');
        final token = 'tok-${++_counter}';
        _tokens[token] = user.id;
        return _json({'redirect': false, 'token': token, 'user': _userJson(user)}, headers: {'set-auth-token': token});
      case 'GET /api/auth/get-session':
        final user = _userFor(request);
        return user == null ? _json(null) : _json({'user': _userJson(user), 'session': {'id': 's'}});
      case 'POST /api/auth/sign-out':
        _tokens.remove(request.headers['Authorization']?.replaceFirst('Bearer ', ''));
        return _json({'success': true});
      case 'POST /api/auth/send-verification-email':
        sentEmails.add('verify:${body['email']}');
        return _json({'status': true});
      case 'POST /api/auth/request-password-reset':
        sentEmails.add('reset:${body['email']}');
        return _json({'status': true, 'message': 'If this email exists in our system, check your email for the reset link'});
      case 'GET /api/consent-policies/current':
        return _json({'version': policyVersion, 'effectiveDate': '2026-11-08', 'summary': 'Draf kebijakan untuk pengujian.', 'purposes': _purposes});
    }

    final user = _userFor(request);
    if (user == null) return _appError(401, 'UNAUTHENTICATED', 'Sesi tidak valid atau sudah berakhir.');

    switch (key) {
      case 'POST /api/auth/change-password':
        if (user.password != body['currentPassword']) return _authError(400, 'INVALID_PASSWORD', 'Invalid password');
        user.password = body['newPassword'] as String;
        return _json({'status': true});
      case 'GET /api/auth/list-sessions':
        final current = request.headers['Authorization']!.substring(7);
        return _json([
          for (final entry in _tokens.entries.where((e) => e.value == user.id))
            {'id': entry.key, 'token': entry.key, 'userAgent': entry.key == current ? 'beOkay-test' : 'Perangkat lain', 'ipAddress': '', 'createdAt': DateTime.utc(2026, 11, 8).toIso8601String()},
        ]);
      case 'POST /api/auth/revoke-other-sessions':
        final current = request.headers['Authorization']!.substring(7);
        _tokens.removeWhere((token, id) => id == user.id && token != current);
        return _json({'status': true});
      case 'GET /api/me/onboarding':
        return _json(_onboarding(user));
      case 'GET /api/me/today':
        if (!_active(user.id, 'health_data_processing') || !_active(user.id, 'descriptive_summaries')) {
          return _appError(403, 'CONSENT_REQUIRED', 'Persetujuan diperlukan.');
        }
        return _json({
          'displayName': user.name,
          'date': '2026-11-09',
          'greeting': 'Selamat pagi',
          'timezone': _prefsJson()['timezone'],
          'glucoseUnit': _prefsJson()['glucoseUnit'],
          'generatedAt': '2026-11-09T02:00:00Z',
          'metrics': [for (final domain in ['glucose', 'nutrition', 'activity', 'medication']) {'domain': domain, 'availability': 'NOT_IMPLEMENTED', 'value': null}],
        });
      case 'PATCH /api/me/onboarding':
        if (body['expectedVersion'] != null && body['expectedVersion'] != _version) return _appError(409, 'VERSION_CONFLICT', 'Konflik versi.');
        if (_introSeenAt == null) {
          _introSeenAt = DateTime.now();
          _version++;
        }
        return _json(_onboarding(user));
      case 'POST /api/me/onboarding/complete':
        if (_completedAt == null) {
          final missing = (_onboarding(user)['steps'] as List).where((s) => s['done'] == false).map((s) => s['key']).toList();
          if (missing.isNotEmpty) return _appError(409, 'ONBOARDING_INCOMPLETE', 'Masih ada langkah yang belum selesai.', details: {'missingSteps': missing});
          _completedAt = DateTime.now();
          _version++;
        }
        return _json(_onboarding(user));
      case 'GET /api/me/consents':
        return _json(_consentOverview(user.id));
      case 'POST /api/me/consents':
        if (body['policyVersion'] != policyVersion) return _appError(422, 'POLICY_VERSION_MISMATCH', 'Versi kebijakan sudah berubah.');
        for (final purpose in (body['purposes'] as List).cast<String>()) {
          if (_active(user.id, purpose)) continue;
          _consents.add({'id': 'c${++_counter}', 'userId': user.id, 'purpose': purpose, 'policyVersion': policyVersion, 'grantedAt': DateTime.now().toUtc().toIso8601String(), 'withdrawnAt': null, 'source': body['source'] ?? 'api'});
        }
        return _json(_consentOverview(user.id));
      case 'POST /api/me/consents/withdraw':
        for (final purpose in (body['purposes'] as List).cast<String>()) {
          for (final c in _consents.where((c) => c['userId'] == user.id && c['purpose'] == purpose && c['withdrawnAt'] == null)) {
            c['withdrawnAt'] = DateTime.now().toUtc().toIso8601String();
          }
        }
        return _json(_consentOverview(user.id));
      case 'GET /api/me/profile':
        return _json(_profileJson(user));
      case 'PATCH /api/me/profile':
        if (body.containsKey('displayName')) user.name = body['displayName'] as String;
        _profile = {...?_profile, if (body.containsKey('birthYear')) 'birthYear': body['birthYear']};
        return _json(_profileJson(user));
      case 'GET /api/me/preferences':
        return _json(_prefsJson());
      case 'PATCH /api/me/preferences':
        _prefs = {...?_prefs, ...body};
        return _json(_prefsJson());
    }

    if (path == '/api/me/health-profile') {
      if (!_active(user.id, 'health_data_processing')) return _appError(403, 'CONSENT_REQUIRED', 'Persetujuan yang diperlukan belum diberikan atau sudah ditarik.', details: {'purpose': 'health_data_processing'});
      if (request.method == 'GET') return _json(_healthJson());
      if (request.method == 'PUT') {
        if (body['diagnosisStatus'] != 'diagnosed' && (body['diabetesType'] != null || body['diagnosedYear'] != null)) {
          return _appError(422, 'DETAILS_REQUIRE_DIAGNOSIS', 'Tipe dan tahun diagnosis hanya diisi bila terdiagnosis.');
        }
        _health = {'diagnosisStatus': body['diagnosisStatus'], 'diabetesType': body['diabetesType'], 'diagnosedYear': body['diagnosedYear'], 'treatmentContext': body['treatmentContext'] ?? []};
        return _json(_healthJson());
      }
    }
    return _appError(404, 'NOT_FOUND', 'Rute tidak ditemukan.');
  }
}

class _User {
  _User(this.id, this.email, this.name, this.password);

  final String id;
  final String email;
  String name;
  String password;
  bool verified = false;
}
