import 'package:agrobenta_mobile/core/theme/app_input_border.dart';
import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/widgets/field_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The approved field style: a label above a box, with the text, the icons
/// and a dropdown's arrow all sitting on the box rather than on the label.
void main() {
  Future<void> pump(WidgetTester tester, Widget field) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Align(alignment: Alignment.topLeft, child: field),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The box Material draws the border around: the field without the label
  /// band above it.
  Rect boxOf(WidgetTester tester, Finder field) {
    final Rect whole = tester.getRect(
      find.descendant(of: field, matching: find.byType(InputDecorator)),
    );
    return Rect.fromLTRB(
      whole.left,
      whole.top + AppInputs.labelBand,
      whole.right,
      whole.bottom,
    );
  }

  testWidgets('a labelled field puts the label above the box, flush left', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      TextFormField(
        initialValue: 'Ana Reyes',
        decoration: const InputDecoration(label: FieldLabel('Full name')),
      ),
    );

    final Finder field = find.byType(TextFormField);
    final Rect box = boxOf(tester, field);
    final Rect label = tester.getRect(find.text('Full name'));
    final Rect text = tester.getRect(find.text('Ana Reyes'));

    // The label ends above the box and starts at its left edge.
    expect(label.bottom, lessThanOrEqualTo(box.top));
    expect(label.left, closeTo(box.left, 1));

    // The text is inside the box, inset and vertically centred.
    expect(text.left, closeTo(box.left + AppInputs.horizontalPadding, 1));
    expect(text.center.dy, closeTo(box.center.dy, 1.5));

    // The box is about the design's 46.
    expect(box.height, inInclusiveRange(44, 49));
  });

  testWidgets('a field icon is centred on the box, not on the whole field', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      TextFormField(
        decoration: const InputDecoration(
          label: FieldLabel('Email Address', hasPrefixIcon: true),
          prefixIcon: FieldIcon(Icon(Icons.mail_outline)),
        ),
      ),
    );

    final Rect box = boxOf(tester, find.byType(TextFormField));
    final Rect icon = tester.getRect(find.byIcon(Icons.mail_outline));
    final Rect label = tester.getRect(find.text('Email Address'));

    expect(icon.center.dy, closeTo(box.center.dy, 1.5));
    // The label still lines up with the box, not with the text after the icon.
    expect(label.left, closeTo(box.left, 1));
  });

  testWidgets('a dropdown arrow sits on the box, in from the right edge', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      DropdownButtonFormField<String>(
        icon: const FieldDropdownIcon(),
        initialValue: 'a',
        decoration: const InputDecoration(label: FieldLabel('Barangay')),
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(value: 'a', child: Text('Banlasan')),
        ],
        onChanged: (_) {},
      ),
    );

    final Rect box = boxOf(
      tester,
      find.byType(DropdownButtonFormField<String>),
    );
    final Rect arrow = tester.getRect(find.byIcon(Icons.keyboard_arrow_down));
    final Rect value = tester.getRect(find.text('Banlasan'));

    expect(arrow.center.dy, closeTo(box.center.dy, 1.5));
    expect(value.center.dy, closeTo(box.center.dy, 1.5));
    expect(box.right - arrow.right, inInclusiveRange(8, 16));
  });

  testWidgets('a field with no label has no band above the box', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      const TextField(
        decoration: InputDecoration(
          hintText: 'Search livestock',
          contentPadding: AppInputs.plainPadding,
        ),
      ),
    );

    final Rect whole = tester.getRect(find.byType(InputDecorator));
    final Rect hint = tester.getRect(find.text('Search livestock'));

    expect(whole.height, inInclusiveRange(44, 49));
    expect(hint.center.dy, closeTo(whole.center.dy, 1.5));
  });
}
