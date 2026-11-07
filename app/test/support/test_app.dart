import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/app.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/core/widgets/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_backend.dart';

class TestHarness {
  TestHarness({FakeBackend? backend, TokenStorage? tokens})
      : backend = backend ?? FakeBackend(),
        tokens = tokens ?? MemoryTokenStorage();

  final FakeBackend backend;
  final TokenStorage tokens;
  final GlobalKey boundary = GlobalKey();

  Future<void> pump(WidgetTester tester, {Size size = const Size(390, 844)}) async {
    await initializeDateFormatting('id_ID');
    if (Platform.environment['SHOT_DIR'] != null) {
      await (FontLoader('Inter')
        ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Inter-Bold.ttf'))).load();
      await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          tokenStorageProvider.overrideWithValue(tokens),
          httpClientProvider.overrideWithValue(backend.client),
        ],
        child: RepaintBoundary(key: boundary, child: const BeOkayApp()),
      ),
    );
    await settle(tester);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    final directory = Platform.environment['SHOT_DIR'];
    if (directory == null) return;
    await tester.runAsync(() async {
      final renderObject = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await renderObject.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text).hitTestable();
    await tester.ensureVisible(find.text(text).first);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(finder.first);
    await settle(tester);
  }

  Future<void> fill(WidgetTester tester, String label, String value) async {
    final field = find.byWidgetPredicate((widget) => widget is AppTextField && widget.label == label);
    final input = find.descendant(of: field, matching: find.byType(TextFormField));
    await tester.ensureVisible(input);
    await tester.enterText(input, value);
    await tester.pump(const Duration(milliseconds: 50));
  }
}
