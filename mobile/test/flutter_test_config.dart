import 'dart:async';

import 'package:intl/date_symbol_data_local.dart';

/// Runs before every test file in this directory.
///
/// `intl` bundles date symbols for `en_US` only, and `AppFormatters` formats
/// dates with the `en_PH` locale, so `DateFormat(..., 'en_PH')` throws a
/// `LocaleDataException` unless the locale has been initialised. `main()` does
/// this for the app; this file is the equivalent for the suite, so no individual
/// test has to remember it.
///
/// Dart's test runner picks this up automatically for everything under
/// `test/`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await initializeDateFormatting('en_PH');
  await testMain();
}
