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

  Finder barangayDropdown() => find.ancestor(
    of: find.text('Barangay'),
    matching: find.byType(DropdownButtonFormField<String>),
  );

  testWidgets('shows fixed locality fields and the complete 20-name catalog', (
    WidgetTester tester,
  ) async {
    await pumpSelector(tester, onChanged: (_) {});

    expect(find.text('Central Visayas (Region VII) · Bohol'), findsOneWidget);
    expect(find.text('Trinidad'), findsOneWidget);
    final catalog = TrinidadLocationScope.readOf(
      tester.element(find.byType(_LocationHarness)),
    );
    expect(catalog.state.catalog!.barangays, trinidadBarangayNames);

    await tester.tap(barangayDropdown());
    await tester.pumpAndSettle();
    expect(find.text('Banlasan'), findsOneWidget);
  });

  testWidgets('selection and Street / Purok edits return a location model', (
    WidgetTester tester,
  ) async {
    final List<TrinidadLocation?> changes = <TrinidadLocation?>[];
    await pumpSelector(tester, onChanged: changes.add);

    await tester.tap(barangayDropdown());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banlasan').last);
    await tester.pumpAndSettle();
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

  testWidgets(
    'requires a barangay but permits an empty optional Street/Purok',
    (WidgetTester tester) async {
      await pumpSelector(tester, onChanged: (_) {});

      await tester.tap(find.widgetWithText(FilledButton, 'Validate'));
      await tester.pump();
      expect(find.text('Select a barangay.'), findsOneWidget);

      await tester.tap(barangayDropdown());
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
      tester
          .widget<DropdownButtonFormField<String>>(barangayDropdown())
          .initialValue,
      'San Isidro',
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
      tester
          .widget<DropdownButtonFormField<String>>(barangayDropdown())
          .initialValue,
      isNull,
    );
  });

  testWidgets('read-only mode disables editing controls', (
    WidgetTester tester,
  ) async {
    await pumpSelector(
      tester,
      initialValue: const TrinidadLocation(barangay: 'Poblacion'),
      readOnly: true,
      onChanged: (_) {},
    );

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('Poblacion'), findsOneWidget);
  });
}
