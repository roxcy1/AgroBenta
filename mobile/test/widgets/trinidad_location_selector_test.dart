import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/trinidad_location/state/trinidad_location_scope.dart';
import 'package:agrobenta_mobile/models/trinidad_location.dart';
import 'package:agrobenta_mobile/widgets/trinidad_location_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/auth_fakes.dart';
import '../support/trinidad_location_fakes.dart';

class _LocationHarness extends StatefulWidget {
  const _LocationHarness({
    this.initialValue,
    this.legacyAddress,
    this.isRequired = true,
    this.readOnly = false,
    required this.onChanged,
    super.key,
  });

  final TrinidadLocation? initialValue;
  final String? legacyAddress;
  final bool isRequired;
  final bool readOnly;
  final ValueChanged<TrinidadLocation?> onChanged;

  @override
  State<_LocationHarness> createState() => _LocationHarnessState();
}

class _LocationHarnessState extends State<_LocationHarness> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  TrinidadLocation? value;
  bool? lastValidationResult;

  @override
  void initState() {
    super.initState();
    value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Form(
              key: formKey,
              child: TrinidadLocationSelector(
                value: value,
                legacyAddress: widget.legacyAddress,
                maxFormattedLength: TrinidadLocation.profileAddressMax,
                isRequired: widget.isRequired,
                readOnly: widget.readOnly,
                onChanged: (TrinidadLocation? next) {
                  setState(() => value = next);
                  widget.onChanged(next);
                },
              ),
            ),
            FilledButton(
              onPressed: () => setState(
                () => lastValidationResult = formKey.currentState!.validate(),
              ),
              child: const Text('Validate'),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  Future<void> pumpSelector(
    WidgetTester tester, {
    TrinidadLocation? initialValue,
    String? legacyAddress,
    bool isRequired = true,
    bool readOnly = false,
    required ValueChanged<TrinidadLocation?> onChanged,
  }) async {
    await tester.pumpWidget(
      TrinidadLocationTestScope(
        tokenStore: FakeTokenStore('mobile-token'),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: _LocationHarness(
            key: UniqueKey(),
            initialValue: initialValue,
            legacyAddress: legacyAddress,
            isRequired: isRequired,
            readOnly: readOnly,
            onChanged: onChanged,
          ),
        ),
      ),
    );
    for (int frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder barangaySelector() => find.byKey(trinidadBarangayFieldKey);

  Finder barangayFormField() => find.byKey(trinidadBarangayFormFieldKey);

  testWidgets('shows fixed locality and all catalog barangays in the sheet', (
    WidgetTester tester,
  ) async {
    await pumpSelector(tester, onChanged: (_) {});

    expect(find.text('Central Visayas (Region VII) · Bohol'), findsOneWidget);
    expect(find.text('Trinidad'), findsOneWidget);
    final catalog = TrinidadLocationScope.readOf(
      tester.element(find.byType(_LocationHarness)),
    );
    expect(catalog.state.catalog!.barangays, trinidadBarangayNames);

    await tester.tap(barangaySelector());
    await tester.pumpAndSettle();
    final BottomSheet sheet = tester.widget<BottomSheet>(
      find.byType(BottomSheet),
    );
    expect(sheet.showDragHandle, isFalse);
    expect(
      sheet.shape,
      isA<RoundedRectangleBorder>().having(
        (RoundedRectangleBorder shape) => shape.borderRadius,
        'top corner radius',
        const BorderRadius.vertical(top: Radius.circular(24)),
      ),
    );
    final Finder dragHandle = find.byKey(trinidadBarangayDragHandleKey);
    expect(tester.getSize(dragHandle), const Size(32, 4));
    expect(
      tester.getCenter(dragHandle).dx,
      closeTo(tester.getSize(find.byType(BottomSheet)).width / 2, 0.5),
    );
    expect(tester.getSize(find.byType(BottomSheet)).height, lessThan(540));
    final Text heading = tester.widget<Text>(find.text('Select Barangay'));
    expect(heading.style?.fontSize, 18);
    expect(heading.style?.fontWeight, FontWeight.w600);
    final Text subtitle = tester.widget<Text>(
      find.text('Choose your barangay'),
    );
    expect(subtitle.style?.fontSize, 14);
    final TextField searchField = tester.widget<TextField>(
      find.byKey(trinidadBarangaySearchFieldKey),
    );
    expect(searchField.decoration?.hintText, 'Search barangay...');
    expect(searchField.decoration?.filled, isFalse);
    expect(searchField.decoration?.border, InputBorder.none);
    expect(searchField.decoration?.enabledBorder, InputBorder.none);
    expect(searchField.decoration?.focusedBorder, InputBorder.none);
    expect(find.text('Select Barangay'), findsOneWidget);
    expect(find.text('Choose your barangay'), findsOneWidget);
    expect(find.text('20 barangays available'), findsOneWidget);
    expect(find.text('Banlasan'), findsOneWidget);
    await tester.drag(
      find.byKey(trinidadBarangayResultsKey),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tagum Sur'), findsOneWidget);
  });

  testWidgets(
    'search trims whitespace, ignores case, and updates results immediately',
    (WidgetTester tester) async {
      await pumpSelector(tester, onChanged: (_) {});
      await tester.tap(barangaySelector());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(trinidadBarangaySearchFieldKey),
        ' pOb ',
      );
      await tester.pump();

      expect(find.text('1 barangay found'), findsOneWidget);
      expect(find.text('Poblacion'), findsOneWidget);
      expect(find.text('Banlasan'), findsNothing);

      await tester.enterText(find.byKey(trinidadBarangaySearchFieldKey), 'san');
      await tester.pump();
      expect(find.text('4 barangays found'), findsOneWidget);
      expect(find.text('Banlasan'), findsOneWidget);
      expect(find.text('San Isidro'), findsOneWidget);
      expect(find.text('San Vicente'), findsOneWidget);
      expect(find.text('Santo Tomas'), findsOneWidget);
    },
  );

  testWidgets('no matches are explicit and cannot be selected', (
    WidgetTester tester,
  ) async {
    final List<TrinidadLocation?> changes = <TrinidadLocation?>[];
    await pumpSelector(tester, onChanged: changes.add);
    await tester.tap(barangaySelector());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(trinidadBarangaySearchFieldKey),
      'not a barangay',
    );
    await tester.pump();

    expect(find.text('0 barangays found'), findsOneWidget);
    expect(find.text('No barangays found'), findsOneWidget);
    expect(changes, isEmpty);
  });

  testWidgets('search remains visible with the keyboard on a small screen', (
    WidgetTester tester,
  ) async {
    final Size originalSize = tester.view.physicalSize;
    final double originalDpr = tester.view.devicePixelRatio;
    final FakeViewPadding originalInsets = tester.view.viewInsets;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.physicalSize = originalSize;
      tester.view.devicePixelRatio = originalDpr;
      tester.view.viewInsets = originalInsets;
    });

    await pumpSelector(tester, onChanged: (_) {});
    expect(
      tester.takeException(),
      isNull,
      reason: 'selector fits before opening the sheet',
    );
    await tester.tap(barangaySelector());
    await tester.pumpAndSettle();
    final Finder search = find.byKey(trinidadBarangaySearchFieldKey);
    expect(search, findsOneWidget);
    expect(search.hitTestable(), findsOneWidget);
    await tester.tap(search);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'empty state fits with keyboard',
    );
    expect(search.hitTestable(), findsOneWidget);
    expect(
      tester.widget<TextField>(search).decoration?.focusedBorder,
      InputBorder.none,
    );
    await tester.enterText(search, 'tagum');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'results fit with keyboard');

    expect(find.text('2 barangays found'), findsOneWidget);
    expect(find.text('Tagum Norte'), findsOneWidget);
    expect(find.text('Tagum Sur'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection closes the sheet and returns a catalog value', (
    WidgetTester tester,
  ) async {
    final List<TrinidadLocation?> changes = <TrinidadLocation?>[];
    await pumpSelector(tester, onChanged: changes.add);

    await tester.tap(barangaySelector());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banlasan').last);
    await tester.pumpAndSettle();
    expect(find.text('Select Barangay'), findsNothing);
    expect(
      find.descendant(of: barangaySelector(), matching: find.text('Banlasan')),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Street / Purok (optional)'),
      'Purok 3, Sitio Riverside',
    );
    await tester.pump();

    expect(changes.last?.barangay, 'Banlasan');
    expect(changes.last?.streetPurok, 'Purok 3, Sitio Riverside');
    expect(
      changes.last?.formattedAddress(
        municipality: 'Trinidad',
        province: 'Bohol',
      ),
      'Purok 3, Sitio Riverside, Barangay Banlasan, Trinidad, Bohol',
    );
  });

  testWidgets('reopening shows the selected barangay with a checkmark', (
    WidgetTester tester,
  ) async {
    await pumpSelector(
      tester,
      initialValue: const TrinidadLocation(barangay: 'Poblacion'),
      onChanged: (_) {},
    );
    await tester.tap(barangaySelector());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('Poblacion'), findsNWidgets(2));
  });

  testWidgets('dismissing without a selection preserves the previous value', (
    WidgetTester tester,
  ) async {
    final List<TrinidadLocation?> changes = <TrinidadLocation?>[];
    await pumpSelector(
      tester,
      initialValue: const TrinidadLocation(barangay: 'Poblacion'),
      onChanged: changes.add,
    );
    await tester.tap(barangaySelector());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(changes, isEmpty);
    expect(
      find.descendant(of: barangaySelector(), matching: find.text('Poblacion')),
      findsOneWidget,
    );
  });

  testWidgets('an optional address can still clear its barangay selection', (
    WidgetTester tester,
  ) async {
    final List<TrinidadLocation?> changes = <TrinidadLocation?>[];
    await pumpSelector(
      tester,
      initialValue: const TrinidadLocation(barangay: 'Poblacion'),
      isRequired: false,
      onChanged: changes.add,
    );
    await tester.tap(barangaySelector());
    await tester.pumpAndSettle();
    expect(find.text('No barangay selected'), findsOneWidget);
    await tester.tap(find.text('No barangay selected'));
    await tester.pumpAndSettle();

    expect(changes, <TrinidadLocation?>[null]);
    expect(find.text('Select barangay'), findsOneWidget);
  });

  testWidgets(
    'requires a barangay but permits an empty optional Street/Purok',
    (WidgetTester tester) async {
      await pumpSelector(tester, onChanged: (_) {});

      await tester.tap(find.widgetWithText(FilledButton, 'Validate'));
      await tester.pump();
      expect(find.text('Select a barangay.'), findsOneWidget);

      await tester.tap(barangaySelector());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Banlasan').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Validate'));
      await tester.pump();

      expect(
        tester
            .state<_LocationHarnessState>(find.byType(_LocationHarness))
            .lastValidationResult,
        isTrue,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Street / Purok (optional)'),
            )
            .controller!
            .text,
        isEmpty,
      );
    },
  );

  testWidgets('restores saved values and never guesses a legacy barangay', (
    WidgetTester tester,
  ) async {
    await pumpSelector(
      tester,
      initialValue: const TrinidadLocation(
        barangay: 'San Isidro',
        streetPurok: 'Purok 1',
      ),
      onChanged: (_) {},
    );
    expect(
      tester.widget<FormField<String>>(barangayFormField()).initialValue,
      'San Isidro',
    );
    expect(
      find.descendant(
        of: barangaySelector(),
        matching: find.text('San Isidro'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Street / Purok (optional)'),
          )
          .controller!
          .text,
      'Purok 1',
    );

    await pumpSelector(
      tester,
      legacyAddress: 'Trinidad, Bohol',
      onChanged: (_) {},
    );
    expect(find.text('Trinidad, Bohol'), findsOneWidget);
    expect(
      tester.widget<FormField<String>>(barangayFormField()).initialValue,
      isNull,
    );
    expect(
      find.descendant(
        of: barangaySelector(),
        matching: find.text('Select barangay'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('read-only mode disables editing controls', (
    WidgetTester tester,
  ) async {
    final Size originalSize = tester.view.physicalSize;
    final double originalDpr = tester.view.devicePixelRatio;
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.physicalSize = originalSize;
      tester.view.devicePixelRatio = originalDpr;
    });

    await pumpSelector(
      tester,
      initialValue: const TrinidadLocation(barangay: 'Poblacion'),
      readOnly: true,
      onChanged: (_) {},
    );

    expect(find.byKey(trinidadBarangayFieldKey), findsNothing);
    expect(find.text('Poblacion'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
