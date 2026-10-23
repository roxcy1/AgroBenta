import 'package:flutter/widgets.dart';

import '../../../repositories/inquiry_repository.dart';

/// The inquiry repository, for the inquire screen.
///
/// A plain [InheritedWidget] exposing the repository **only** — deliberately
/// not a controller, unlike `SellerVerificationScope`. An inquiry is a
/// one-shot form, not a session state: the screen that owns the request also
/// owns its controller, creating it in `initState` and disposing it in
/// `dispose` (the `ListingDetailScreen` pattern). There is no second screen
/// that needs to see an in-flight submission, and no state worth keeping alive
/// after the route is popped.
///
/// Installed above `MaterialApp` in `main.dart`, so the screen pushed on top
/// of the buyer shell can resolve it the same way any other route does.
class InquiryScope extends InheritedWidget {
  const InquiryScope({
    required this.repository,
    required super.child,
    super.key,
  });

  final InquiryRepository repository;

  /// The repository, registering [context] as a dependency.
  ///
  /// Correct from `build` and below. Calling it during `initState` throws —
  /// use [readOf] there.
  static InquiryRepository of(BuildContext context) {
    final InquiryScope? scope = context
        .dependOnInheritedWidgetOfExactType<InquiryScope>();
    assert(scope != null, 'No InquiryScope found in context.');
    return scope!.repository;
  }

  /// The repository, **without** registering a dependency.
  ///
  /// For `initState`, where a dependency cannot be registered and where
  /// rebuilding the whole screen on every keystroke would be wrong anyway.
  static InquiryRepository readOf(BuildContext context) {
    final InquiryScope? scope = context
        .getInheritedWidgetOfExactType<InquiryScope>();
    assert(scope != null, 'No InquiryScope found in context.');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(InquiryScope oldWidget) =>
      repository != oldWidget.repository;
}
