import 'dart:async';

import 'package:agrobenta_mobile/core/lifecycle/app_visibility.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // `AppVisibility` registers itself with the binding in its constructor.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppVisibility', () {
    late AppVisibility visibility;
    late List<bool> emitted;
    late StreamSubscription<bool> subscription;

    setUp(() {
      visibility = AppVisibility();
      emitted = <bool>[];
      subscription = visibility.changes.listen(emitted.add);
    });

    tearDown(() async {
      await subscription.cancel();
      visibility.dispose();
    });

    test('starts visible', () {
      expect(visibility.isActive, isTrue);
    });

    test('every non-resumed state hides the app, reported once', () async {
      visibility.didChangeAppLifecycleState(AppLifecycleState.inactive);
      visibility.didChangeAppLifecycleState(AppLifecycleState.hidden);
      visibility.didChangeAppLifecycleState(AppLifecycleState.paused);
      await pumpEventQueue();

      expect(visibility.isActive, isFalse);
      expect(emitted, <bool>[false]);
    });

    test('resuming reports visible again', () async {
      visibility.didChangeAppLifecycleState(AppLifecycleState.paused);
      visibility.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();

      expect(visibility.isActive, isTrue);
      expect(emitted, <bool>[false, true]);
    });

    test('a repeated state is not re-emitted', () async {
      visibility.didChangeAppLifecycleState(AppLifecycleState.resumed);
      visibility.didChangeAppLifecycleState(AppLifecycleState.paused);
      visibility.didChangeAppLifecycleState(AppLifecycleState.paused);
      visibility.didChangeAppLifecycleState(AppLifecycleState.resumed);
      visibility.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();

      expect(emitted, <bool>[false, true]);
    });

    test('disposing stops reporting and closes the stream', () async {
      visibility.dispose();
      visibility.didChangeAppLifecycleState(AppLifecycleState.paused);
      await pumpEventQueue();

      expect(emitted, isEmpty);
      expect(visibility.isActive, isTrue);
      // Idempotent, so main.dart does not have to track whether it ran.
      visibility.dispose();
    });
  });
}
