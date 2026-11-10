import 'dart:convert';
import 'dart:io';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/network/api_exception.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/export/data/data_exporter.dart';
import 'package:app/features/export/presentation/export_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Fake implements DataExporter {
  _Fake(this.result);
  final Object result;
  int calls = 0;
  @override
  Future<ExportOutcome> run() async {
    calls++;
    if (result is Exception) throw result as Exception;
    return result as ExportOutcome;
  }
}

Widget _app(DataExporter e) => ProviderScope(
  overrides: [dataExporterProvider.overrideWithValue(e)],
  child: const MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: ExportSection())),
  ),
);

void main() {
  testWidgets(
    'Tap exports once and reports the record count, with a privacy caption',
    (tester) async {
      final fake = _Fake(
        const ExportOutcome(
          counts: {'meals': 3, 'glucoseObservations': 2, 'account': 1},
          bytes: 100,
        ),
      );
      await tester.pumpWidget(_app(fake));
      expect(find.textContaining('tidak disertakan'), findsOneWidget);
      await tester.tap(find.text('Unduh data saya'));
      await tester.pumpAndSettle();
      expect(fake.calls, 1);
      expect(find.textContaining('6 catatan'), findsOneWidget);
    },
  );

  testWidgets(
    'Rate limit and generic failures show readable messages, never a stack trace',
    (tester) async {
      await tester.pumpWidget(
        _app(
          _Fake(
            const ApiException(
              status: 429,
              code: 'EXPORT_RATE_LIMITED',
              message: 'x',
            ),
          ),
        ),
      );
      await tester.tap(find.text('Unduh data saya'));
      await tester.pumpAndSettle();
      expect(find.textContaining('dalam satu jam'), findsOneWidget);

      await tester.pumpWidget(_app(_Fake(Exception('boom'))));
      await tester.tap(find.text('Unduh data saya'));
      await tester.pumpAndSettle();
      expect(
        find.text('Data tidak dapat dibagikan. Coba lagi.'),
        findsOneWidget,
      );
      expect(find.textContaining('boom'), findsNothing);
    },
  );

  test(
    'ApiDataExporter writes the JSON to a temp file, hands it to the sharer, then deletes it',
    () async {
      final tokens = MemoryTokenStorage();
      await tokens.write('t');
      final bundle = {
        'format': 'beokay-export-v1',
        'generatedAt': '2026-11-09T05:00:00.000Z',
        'counts': {'meals': 2},
        'data': {'meals': []},
      };
      final dir = await Directory.systemTemp.createTemp('beokay-export-test');
      addTearDown(() => dir.delete(recursive: true));
      String? sharedName, sharedText;
      final exporter = ApiDataExporter(
        ApiClient(
          tokens: tokens,
          baseUrl: 'http://test',
          client: MockClient(
            (r) async => http.Response(
              jsonEncode(bundle),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
        tempDir: () async => dir,
        share: (path, name) async {
          sharedName = name;
          sharedText = await File(path).readAsString();
        },
      );
      final out = await exporter.run();
      expect(sharedName, 'beokay-data-2026-11-09.json');
      expect(jsonDecode(sharedText!)['format'], 'beokay-export-v1');
      expect(out.records, 2);
      expect(dir.listSync(), isEmpty); // berkas sementara dihapus
    },
  );
}
