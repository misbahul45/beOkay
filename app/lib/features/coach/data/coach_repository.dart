import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/account_scoped_repository.dart';
import '../../../core/network/api_exception.dart';

class Recommendation {
  Recommendation.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      status = j['status'] as String,
      version = j['version'] as int,
      title = j['title'] as String,
      explanation = j['explanation'] as String,
      source =
          ((j['candidate'] as Map<String, dynamic>)['provenance'] as String?) ??
          '',
      name = (j['candidate'] as Map<String, dynamic>)['name'] as String,
      per100g =
          ((j['candidate'] as Map<String, dynamic>)['per100g']
                  as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, v as num?)),
      dataCoverage = j['dataCoverage'] as String,
      limitations = [for (final l in (j['limitations'] as List)) l as String],
      rankingReason = j['rankingReason'] as String,
      runId = (j['runId'] as String?) ?? '',
      textSource = (j['textSource'] as String?) ?? 'TEMPLATE',
      type = (j['type'] as String?) ?? 'NUTRITION',
      activityType =
          (j['activity'] as Map<String, dynamic>?)?['type'] as String?,
      activityMinutes =
          (j['activity'] as Map<String, dynamic>?)?['durationMinutes'] as int?,
      expiresAt = DateTime.parse(j['expiresAt'] as String);
  final String runId, textSource;
  bool get writtenByModel => textSource == 'LLM';
  final String id,
      status,
      title,
      explanation,
      source,
      name,
      dataCoverage,
      rankingReason,
      type;
  final String? activityType;
  final int? activityMinutes;
  bool get isActivity => type == 'ACTIVITY';
  final int version;
  final Map<String, num?> per100g;
  final List<String> limitations;
  final DateTime expiresAt;
  bool get offered => status == 'OFFERED';
}

class CoachRun {
  CoachRun.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      status = j['status'] as String,
      message = j['message'] as String?,
      consentRequired = j['consentRequired'] == true,
      turn = (j['turn'] as int?) ?? 1,
      intent = (j['intent'] as String?) ?? '',
      recommendations = [
        for (final r in (j['recommendations'] as List))
          Recommendation.fromJson(r as Map<String, dynamic>),
      ];
  final String id, status, intent;
  final int turn;
  final String? message;
  bool get settled =>
      !const ['CREATED', 'VALIDATING', 'RUNNING'].contains(status);
  final bool consentRequired;
  final List<Recommendation> recommendations;
  bool get waiting => status == 'WAITING_FOR_USER';
}

class ActivityPlan {
  ActivityPlan.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      recommendationId = j['recommendationId'] as String,
      activityType = j['activityType'] as String,
      minutes = j['durationMinutes'] as int,
      plannedFor = j['plannedFor'] as String,
      measuredKind =
          (j['measuredOutcome'] as Map<String, dynamic>?)?['kind'] as String?,
      status = j['status'] as String;
  final String id, recommendationId, activityType, plannedFor, status;

  /// Hasil TERUKUR dari catatan nyata (bukan laporan sendiri); null bila belum ada.
  final String? measuredKind;
  final int minutes;
  String get label => switch (activityType) {
    'walking' => 'Jalan kaki',
    'cycling' => 'Bersepeda',
    'running' => 'Lari',
    'strength' => 'Latihan kekuatan',
    _ => 'Aktivitas',
  };
  String get statusLabel => switch (status) {
    'CONFIRMED' => 'Direncanakan',
    'COMPLETED' => 'Selesai',
    'SKIPPED' => 'Dilewati',
    _ => status,
  };
}

class PlannedMeal {
  PlannedMeal.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      recommendationId = j['recommendationId'] as String,
      name = j['name'] as String,
      source = j['source'] as String,
      measuredKind =
          (j['measuredOutcome'] as Map<String, dynamic>?)?['kind'] as String?,
      status = j['status'] as String;
  final String id, recommendationId, name, source, status;
  final String? measuredKind;
  String get statusLabel => switch (status) {
    'PLANNED' => 'Direncanakan',
    'CONSUMED' => 'Sudah dimakan',
    'SKIPPED' => 'Tidak jadi',
    _ => status,
  };
}

/// Satu pembaruan dari aliran SSE. `run` hanya terisi pada jenis `state` (akhir aliran).
class RunUpdate {
  const RunUpdate({required this.type, this.payload = const {}, this.run});
  final String type;
  final Map<String, dynamic> payload;
  final CoachRun? run;

  /// Teks kemajuan untuk pengguna; null bila peristiwa itu tidak perlu ditampilkan.
  String? get label => switch (type) {
    'RUN_CREATED' => 'Menyiapkan…',
    'SAFETY_SCREEN' => 'Memeriksa permintaan…',
    'NODE_ENTER' => switch (payload['node']) {
      'gather_context' => 'Membaca preferensimu…',
      'retrieve_candidates' => 'Mencari di sumber gizi…',
      'validate_and_filter' => 'Memeriksa alergi dan sumber…',
      'rank' => 'Menyusun urutan…',
      'build_candidates' => 'Menyusun pilihan dari riwayatmu…',
      _ => null,
    },
    'LLM_TEXT' => 'Menulis penjelasan…',
    _ => null,
  };
}

class CoachRepository extends AccountScopedRepository {
  CoachRepository(super.api, {required super.isCurrentAccount});

  /// `background`: balas segera (202) dan ikuti kemajuan lewat [watchRun]. `previousRunId`: giliran lanjutan dalam percakapan.
  Future<CoachRun> createRun({
    required String idempotencyKey,
    required String message,
    String? query,
    String? previousRunId,
    bool background = false,
  }) async => CoachRun.fromJson(
    (await write('POST', '/api/me/agent/runs${background ? '?async=1' : ''}', {
      'idempotencyKey': idempotencyKey,
      'message': message,
      'query': ?query,
      'previousRunId': ?previousRunId,
    })).object,
  );

  /// SSE: peristiwa kemajuan, diakhiri satu pembaruan `state` berisi run lengkap. Melempar [ApiException] bila aliran gagal dibuka.
  Stream<RunUpdate> watchRun(String id, {int after = 0}) async* {
    final token = await api.tokens.read();
    final req =
        http.Request(
            'GET',
            Uri.parse(
              '${api.baseUrl}/api/me/agent/runs/$id/stream${after > 0 ? '?after=$after' : ''}',
            ),
          )
          ..headers.addAll({
            'Accept': 'text/event-stream',
            'Authorization': ?(token == null ? null : 'Bearer $token'),
          });
    final http.StreamedResponse res;
    try {
      res = await api.client.send(req).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const ApiException(
        status: 0,
        code: ApiException.networkCode,
        message: 'Server tidak merespons. Coba lagi.',
      );
    } on http.ClientException {
      throw const ApiException(
        status: 0,
        code: ApiException.networkCode,
        message: 'Tidak bisa terhubung. Periksa koneksimu.',
      );
    }
    if (res.statusCode != 200) {
      throw ApiException(
        status: res.statusCode,
        code: 'STREAM_FAILED',
        message: 'Tidak bisa mengikuti kemajuan.',
      );
    }
    String? event;
    final data = StringBuffer();
    await for (final line
        in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (event != null && data.isNotEmpty) {
          final decoded = jsonDecode(data.toString()) as Map<String, dynamic>;
          yield event == 'state'
              ? RunUpdate(type: 'state', run: CoachRun.fromJson(decoded))
              : RunUpdate(
                  type: event,
                  payload:
                      (decoded['payload'] as Map<String, dynamic>?) ?? const {},
                );
        }
        event = null;
        data.clear();
      } else if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        data.write(line.substring(5).trim());
      }
    }
  }

  /// Pemulihan setelah aplikasi dimulai ulang: run yang masih menunggu keputusan, kronologis. Kosong bila persetujuan dicabut.
  Future<List<CoachRun>> pendingRuns() async => [
    for (final v
        in (await api.get('/api/me/agent/pending')).object['items'] as List)
      CoachRun.fromJson(v as Map<String, dynamic>),
  ];

  Future<CoachRun> getRun(String id) async =>
      CoachRun.fromJson((await api.get('/api/me/agent/runs/$id')).object);

  Future<CoachRun> cancel(String id) async => CoachRun.fromJson(
    (await write('POST', '/api/me/agent/runs/$id/cancel', {})).object,
  );

  /// `operationId` dibuat sekali per niat pengguna dan dipakai ulang saat mengulang, supaya server tidak menulis dua kali.
  Future<void> decide(
    Recommendation r, {
    required bool accept,
    required String operationId,
  }) async => write('POST', '/api/me/agent/recommendations/${r.id}/decision', {
    'operationId': operationId,
    'decision': accept ? 'ACCEPT' : 'REJECT',
    'expectedVersion': r.version,
  });

  Future<void> feedback(
    String recommendationId, {
    required bool consumed,
    required String operationId,
  }) async => write(
    'POST',
    '/api/me/agent/recommendations/$recommendationId/feedback',
    {
      'operationId': operationId,
      'kind': consumed ? 'CONSUMED' : 'NOT_CONSUMED',
    },
  );

  Future<void> activityFeedback(
    String recommendationId, {
    required bool completed,
    required String operationId,
  }) async => write(
    'POST',
    '/api/me/agent/recommendations/$recommendationId/feedback',
    {'operationId': operationId, 'kind': completed ? 'COMPLETED' : 'SKIPPED'},
  );

  Future<List<ActivityPlan>> activityPlans() async => [
    for (final v
        in (await api.get('/api/me/activity-plans')).object['items'] as List)
      ActivityPlan.fromJson(v as Map<String, dynamic>),
  ];

  Future<List<PlannedMeal>> plannedMeals() async => [
    for (final v
        in (await api.get('/api/me/planned-meals')).object['items'] as List)
      PlannedMeal.fromJson(v as Map<String, dynamic>),
  ];
}
