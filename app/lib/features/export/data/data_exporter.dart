import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';

/// Mengunduh data milik sendiri (`GET /api/me/export`) lalu menyerahkannya ke lembar bagikan sistem.
/// Berkas sementara dihapus setelah lembar bagikan ditutup. Hak ini tidak bergantung pada consent.
abstract interface class DataExporter {
  Future<ExportOutcome> run();
}

class ExportOutcome {
  const ExportOutcome({required this.counts, required this.bytes});
  final Map<String, int> counts;
  final int bytes;
  int get records => counts.values.fold(0, (a, b) => a + b);
}

/// Menulis berkas dan membagikannya; dipisah agar tes tidak menyentuh plugin platform.
typedef FileSharer = Future<void> Function(String path, String name);

Future<void> _shareFile(String path, String name) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(path, mimeType: 'application/json', name: name)],
      subject: 'Data beOkay',
    ),
  );
}

class ApiDataExporter implements DataExporter {
  ApiDataExporter(this.api, {this.share = _shareFile, this.tempDir});
  final ApiClient api;
  final FileSharer share;
  final Future<Directory> Function()? tempDir;

  @override
  Future<ExportOutcome> run() async {
    final res = await api.get('/api/me/export');
    final text = jsonEncode(res.object);
    final stamp =
        (res.object['generatedAt'] as String? ??
                DateTime.now().toIso8601String())
            .substring(0, 10);
    final name = 'beokay-data-$stamp.json';
    final dir = await (tempDir ?? getTemporaryDirectory)();
    final file = File('${dir.path}/$name');
    await file.writeAsString(text, flush: true);
    try {
      await share(file.path, name);
    } finally {
      if (await file.exists()) await file.delete();
    }
    final counts = <String, int>{
      for (final e in ((res.object['counts'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toInt(),
    };
    return ExportOutcome(counts: counts, bytes: utf8.encode(text).length);
  }
}

final dataExporterProvider = Provider<DataExporter>(
  (ref) => ApiDataExporter(ref.watch(apiClientProvider)),
);
