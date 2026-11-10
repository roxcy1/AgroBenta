import 'dart:typed_data';

import 'package:agrobenta_mobile/features/receipts/services/receipt_png_exporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('captures a painted boundary as PNG bytes', (
    WidgetTester tester,
  ) async {
    final GlobalKey key = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: const SizedBox(
              width: 300,
              height: 200,
              child: ColoredBox(color: Colors.green),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Uint8List? bytes = await tester.runAsync(
      () => const RepaintBoundaryPngExporter().capture(key),
    );

    expect(bytes, isNotNull);
    expect(bytes!, isNotEmpty);
    expect(
      bytes.take(8).toList(),
      <int>[137, 80, 78, 71, 13, 10, 26, 10],
      reason: 'toImage must encode a real PNG',
    );
  });

  test('refuses a boundary that is not painted', () async {
    await expectLater(
      const RepaintBoundaryPngExporter().capture(GlobalKey()),
      throwsA(isA<StateError>()),
    );
  });
}
