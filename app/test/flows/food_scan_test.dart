import 'dart:convert';
import 'dart:typed_data';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/nutrition/data/nutrition_repository.dart';
import 'package:app/features/nutrition/presentation/scan/barcode_scan_screen.dart';
import 'package:app/features/nutrition/presentation/scan/food_image_source.dart';
import 'package:app/features/nutrition/presentation/scan/gtin.dart';
import 'package:app/features/nutrition/presentation/scan/scan_hub.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _Picker implements FoodImagePicker {
  int calls = 0;
  @override
  Future<Uint8List?> capture({required bool camera}) async {
    calls++;
    return Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
  }
}

Widget _cam(BuildContext c, void Function(String) onCode, controller) => Center(
  child: TextButton(
    onPressed: () => onCode('4006381333931'),
    child: const Text('simulasi pindai'),
  ),
);

Future<(NutritionRepository, List<http.Request>)> _repo(
  http.Response Function(http.Request) h,
) async {
  final tokens = MemoryTokenStorage();
  await tokens.write('t');
  final seen = <http.Request>[];
  return (
    NutritionRepository(
      ApiClient(
        tokens: tokens,
        baseUrl: 'http://test',
        client: MockClient((r) async {
          seen.add(r);
          return h(r);
        }),
      ),
      isCurrentAccount: () => true,
    ),
    seen,
  );
}

Future<ScanOutcome?> _open(
  WidgetTester tester,
  NutritionRepository repo,
  _Picker picker,
) async {
  ScanOutcome? outcome;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [foodImagePickerProvider.overrideWithValue(picker)],
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  outcome = await showScanHub(ctx, repo, cameraBuilder: _cam),
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('buka'));
  await tester.pumpAndSettle();
  return outcome;
}

Map<String, dynamic> _foodResponse(http.Request r) {
  final b = jsonDecode(r.body) as Map<String, dynamic>;
  return {
    'id': 'f1',
    'name': b['name'],
    'source': b['source'],
    'status': b['status'],
    'per100g': b['per100g'],
  };
}

const _candidate = {
  'externalId': '4006381333931',
  'name': 'Roti uji',
  'brand': null,
  'source': 'Open Food Facts',
  'completeness': 'PARTIAL',
  'per100g': {
    'calories': 260,
    'carbohydrates': 50,
    'protein': null,
    'fat': 3,
    'fiber': null,
  },
};

void main() {
  test('GTIN check digit', () {
    expect(validGtin('4006381333931'), isTrue);
    expect(validGtin('96385074'), isTrue);
    expect(validGtin('4006381333932'), isFalse);
    expect(validGtin('12345'), isFalse);
    expect(validGtin('abcdefgh'), isFalse);
  });

  testWidgets(
    'Barcode: scan → review → saved as an estimate, unknown values stay null',
    (tester) async {
      Map<String, dynamic>? saved;
      final (repo, seen) = await _repo((r) {
        if (r.url.path == '/api/me/foods/barcode/4006381333931') {
          return _json({'status': 'FOUND', 'candidate': _candidate});
        }
        if (r.url.path == '/api/me/foods' && r.method == 'POST') {
          saved = jsonDecode(r.body) as Map<String, dynamic>;
          return _json(_foodResponse(r), 201);
        }
        return _json({}, 404);
      });
      await _open(tester, repo, _Picker());
      await tester.tap(find.text('Pindai kode batang'));
      await tester.pumpAndSettle();
      expect(find.byType(BarcodeScanScreen), findsOneWidget);
      expect(seen, isEmpty); // nothing sent while only the camera is open
      await tester.tap(find.text('simulasi pindai'));
      await tester.pumpAndSettle();
      expect(find.text('Periksa produk'), findsOneWidget);
      expect(find.textContaining('Dari Open Food Facts'), findsOneWidget);
      expect(find.textContaining('2 nilai belum ada'), findsOneWidget);
      await tester.tap(find.text('Simpan sebagai makanan'));
      await tester.pumpAndSettle();
      expect(saved!['status'], 'estimated');
      expect(saved!['source'], 'Open Food Facts');
      expect(saved!['sourceVersion'], '4006381333931');
      expect((saved!['per100g'] as Map)['protein'], isNull);
      expect((saved!['per100g'] as Map)['calories'], 260);
      expect(
        find.text('Catat makanan'),
        findsNothing,
      ); // sheet closed with the saved food
    },
  );

  testWidgets('Barcode not found shows a plain message and offers other ways', (
    tester,
  ) async {
    final (repo, _) = await _repo(
      (r) => _json({'status': 'NOT_FOUND', 'candidate': null}),
    );
    await _open(tester, repo, _Picker());
    await tester.tap(find.text('Pindai kode batang'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('simulasi pindai'));
    await tester.pumpAndSettle();
    expect(find.textContaining('belum ada di Open Food Facts'), findsOneWidget);
    expect(find.text('Foto label gizi'), findsOneWidget);
  });

  testWidgets(
    'Label photo: nothing is sent until the user agrees; result must be reviewed and named',
    (tester) async {
      Map<String, dynamic>? saved;
      final picker = _Picker();
      final (repo, seen) = await _repo((r) {
        if (r.url.path == '/api/me/foods/scan/label') {
          expect(r.headers['content-type'], 'image/jpeg');
          return _json({
            'status': 'READ',
            'candidate': {
              'externalId': 'label',
              'name': 'Produk dari label',
              'brand': null,
              'source': 'Label kemasan (OCR)',
              'completeness': 'PARTIAL',
              'per100g': {
                'calories': 400,
                'carbohydrates': 60,
                'protein': 20,
                'fat': 10,
                'fiber': null,
              },
            },
            'label': {
              'basis': 'per_serving',
              'servingGrams': 30,
              'printed': {},
              'per100g': {},
              'flags': [],
            },
            'rawText': 'x',
          });
        }
        if (r.url.path == '/api/me/foods' && r.method == 'POST') {
          saved = jsonDecode(r.body) as Map<String, dynamic>;
          return _json(_foodResponse(r), 201);
        }
        return _json({}, 404);
      });
      await _open(tester, repo, picker);
      await tester.tap(find.text('Foto label gizi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ambil foto'));
      await tester.pumpAndSettle();
      expect(find.text('Kirim foto untuk dibaca?'), findsOneWidget);
      expect(find.textContaining('Mistral'), findsOneWidget);
      expect(seen, isEmpty);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(seen, isEmpty); // declined → no request

      await tester.tap(find.text('Foto label gizi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pilih dari galeri'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kirim foto'));
      await tester.pumpAndSettle();
      expect(find.text('Periksa hasil label'), findsOneWidget);
      expect(find.textContaining('Dibaca dari foto'), findsOneWidget);
      expect(find.textContaining('takaran saji 30 g'), findsOneWidget);
      // Name is required: OCR never invents a product name.
      await tester.tap(find.text('Simpan sebagai makanan'));
      await tester.pumpAndSettle();
      expect(find.text('Isi nama produk.'), findsOneWidget);
      expect(saved, isNull);
      await tester.enterText(find.byType(TextFormField).first, 'Sereal uji');
      await tester.tap(find.text('Simpan sebagai makanan'));
      await tester.pumpAndSettle();
      expect(saved!['name'], 'Sereal uji');
      expect(saved!['source'], 'Label kemasan (OCR)');
      expect(saved!['status'], 'estimated');
      expect((saved!['per100g'] as Map)['fiber'], isNull);
    },
  );

  testWidgets(
    'Food photo: only names + catalog matches; user picks, weight is never guessed',
    (tester) async {
      final (repo, _) = await _repo((r) {
        if (r.url.path == '/api/me/foods/scan/photo') {
          return _json({
            'status': 'IDENTIFIED',
            'items': [
              {
                'name': 'Nasi putih',
                'confidence': 'high',
                'matches': [
                  {
                    'id': 'f9',
                    'name': 'Nasi putih',
                    'source': 'Pengguna',
                    'status': 'user_reported',
                    'per100g': {
                      'calories': 130,
                      'carbohydrates': 28,
                      'protein': 2.7,
                      'fat': 0.3,
                      'fiber': null,
                    },
                  },
                ],
              },
              {'name': 'Tempe goreng', 'confidence': 'low', 'matches': []},
            ],
          });
        }
        return _json({}, 404);
      });
      final picker = _Picker();
      await _open(tester, repo, picker);
      await tester.tap(find.text('Foto makanan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ambil foto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kirim foto'));
      await tester.pumpAndSettle();
      expect(find.text('Yang terlihat di foto'), findsOneWidget);
      expect(find.textContaining('Bukan data gizi'), findsNothing);
      expect(find.text('Cukup yakin'), findsOneWidget);
      expect(find.text('Ragu'), findsOneWidget);
      expect(find.textContaining('tidak ditebak dari gambar'), findsNothing);
      expect(
        find.textContaining('kkal'),
        findsNothing,
      ); // no nutrition shown for a photo guess
      await tester.tap(find.text('Pakai ini, lalu isi berat'));
      await tester.pumpAndSettle();
      expect(
        find.text('Catat makanan'),
        findsNothing,
      ); // closed with the chosen catalog food
    },
  );

  testWidgets(
    'Model hint is shown only when the server sends one, labelled as an experimental estimate, with no nutrition and nothing recorded',
    (tester) async {
      var withHint = true;
      final (repo, seen) = await _repo((r) {
        if (r.url.path == '/api/me/foods/scan/photo') {
          return _json({
            'status': 'IDENTIFIED',
            'items': [
              {'name': 'Rendang', 'confidence': 'medium', 'matches': []},
            ],
            if (withHint)
              'modelHint': {
                'kind': 'ESTIMATE',
                'label': 'Rendang',
                'probability': 0.913,
                'modelVersion': 'v1',
                'note':
                    'Perkiraan nama hidangan dari model yang masih diuji. Periksa sebelum dipakai; tidak dicatat otomatis.',
              },
          });
        }
        return _json({}, 404);
      });
      Future<void> sendPhoto() async {
        await tester.tap(find.text('Foto makanan'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ambil foto'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kirim foto'));
        await tester.pumpAndSettle();
      }

      await _open(tester, repo, _Picker());
      await sendPhoto();
      expect(find.textContaining('Mungkin juga: Rendang'), findsOneWidget);
      expect(find.textContaining('91% yakin'), findsOneWidget);
      expect(find.textContaining('Periksa dulu'), findsOneWidget);
      expect(find.textContaining('kkal'), findsNothing);
      // Pemanasan model dikirim saat pengguna memilih Foto makanan; gagal (404 di tes) tidak mengganggu alur.
      expect(seen.where((r) => r.url.path == '/api/me/ml/warmup'), isNotEmpty);
      withHint = false;
      await tester.tap(find.text('Bukan ini? Cari manual'));
      await tester.pumpAndSettle();
      await sendPhoto();
      expect(find.textContaining('Mungkin juga'), findsNothing);
    },
  );

  testWidgets(
    'Photo item without a personal match shows nutrition from the reference table, and one tap saves it as an estimate then asks for weight',
    (tester) async {
      Map<String, dynamic>? saved;
      final (repo, _) = await _repo((r) {
        if (r.url.path == '/api/me/foods/scan/photo') {
          return _json({
            'status': 'IDENTIFIED',
            'items': [
              {
                'name': 'Nasi goreng',
                'confidence': 'high',
                'matches': <dynamic>[],
                'reference': [
                  {
                    'code': 'AR123',
                    'name': 'Nasi goreng',
                    'provenance': 'Tabel Komposisi Pangan Indonesia',
                    'source': 'Tabel Komposisi Pangan Indonesia',
                    'completeness': 'COMPLETE',
                    'per100g': {
                      'calories': 212,
                      'carbohydrates': 30,
                      'protein': 6,
                      'fat': 7,
                      'fiber': 1,
                    },
                  },
                ],
              },
              {
                'name': 'Sambal',
                'confidence': 'low',
                'matches': <dynamic>[],
                'reference': <dynamic>[],
              },
            ],
          });
        }
        if (r.url.path == '/api/me/foods' && r.method == 'POST') {
          saved = jsonDecode(r.body) as Map<String, dynamic>;
          return _json({
            'id': 'f9',
            'name': 'Nasi goreng',
            'source': 'Tabel Komposisi Pangan Indonesia',
            'status': 'estimated',
            'per100g': saved!['per100g'],
          }, 201);
        }
        return _json({}, 404);
      });
      await _open(tester, repo, _Picker());
      await tester.tap(find.text('Foto makanan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ambil foto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kirim foto'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('212 kkal per 100 gram'),
        findsOneWidget,
      ); // gizi dari referensi, bukan tebakan gambar
      expect(
        find.text('Gizinya belum ketemu.'),
        findsOneWidget,
      ); // tidak ada padanan → jujur, bukan angka karangan
      expect(find.textContaining('OCR'), findsNothing); // tanpa istilah teknis
      await tester.tap(find.text('Pakai ini, lalu isi berat'));
      await tester.pumpAndSettle();
      expect(saved?['status'], 'estimated');
      expect(saved?['sourceVersion'], 'AR123');
      expect(
        find.text('Yang terlihat di foto'),
        findsNothing,
      ); // layar hasil ditutup dengan makanan terpilih
    },
  );

  testWidgets('Provider not configured is explained, not an error screen', (
    tester,
  ) async {
    final (repo, _) = await _repo(
      (r) => _json({
        'status': 'UNAVAILABLE',
        'code': 'PROVIDER_NOT_CONFIGURED',
        'candidate': null,
        'items': [],
      }),
    );
    await _open(tester, repo, _Picker());
    await tester.tap(find.text('Foto makanan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ambil foto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kirim foto'));
    await tester.pumpAndSettle();
    expect(find.textContaining('belum aktif'), findsOneWidget);
    expect(find.text('Catat makanan'), findsOneWidget);
  });
}
