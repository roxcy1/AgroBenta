import 'dart:async';

import 'package:agrobenta_mobile/core/realtime/refresh_coalescer.dart';
import 'package:flutter_test/flutter_test.dart';

/// A refresh whose completion the test controls.
class _ControlledRefresh {
  final List<Completer<void>> calls = <Completer<void>>[];
  int active = 0;
  int maxActive = 0;

  Future<void> call() {
    final Completer<void> completer = Completer<void>();
    calls.add(completer);
    active++;
    if (active > maxActive) {
      maxActive = active;
    }
    return completer.future.whenComplete(() => active--);
  }

  Future<void> complete(int index, {Object? error}) async {
    if (error == null) {
      calls[index].complete();
    } else {
      calls[index].completeError(error);
    }
    await pumpMicrotasks();
  }
}

Future<void> pumpMicrotasks() => Future<void>.delayed(Duration.zero);

void main() {
  late _ControlledRefresh refresh;
  late bool busy;
  late RefreshCoalescer coalescer;

  setUp(() {
    refresh = _ControlledRefresh();
    busy = false;
    coalescer = RefreshCoalescer(refresh.call, isBusy: () => busy);
  });

  test('an idle request refreshes once', () async {
    coalescer.request();
    await pumpMicrotasks();

    expect(refresh.calls, hasLength(1));
  });

  test('a burst during a refresh produces exactly one trailing refresh', () async {
    coalescer.request();
    coalescer.request();
    coalescer.request();
    coalescer.request();
    await pumpMicrotasks();
    expect(refresh.calls, hasLength(1));

    await refresh.complete(0);
    expect(refresh.calls, hasLength(2));

    await refresh.complete(1);
    expect(refresh.calls, hasLength(2), reason: 'no further events, no loop');
    expect(refresh.maxActive, 1, reason: 'never two requests at once');
  });

  test('a request while the owner is loading runs after that load settles', () async {
    busy = true;
    coalescer.request();
    await pumpMicrotasks();
    expect(refresh.calls, isEmpty, reason: 'no overlap with the owner load');

    busy = false;
    coalescer.settled();
    await pumpMicrotasks();

    expect(refresh.calls, hasLength(1), reason: 'the event is not dropped');
  });

  test('settled without a pending request does nothing', () async {
    coalescer.settled();
    await pumpMicrotasks();

    expect(refresh.calls, isEmpty);
  });

  test('a failed refresh still answers the pending request', () async {
    coalescer.request();
    coalescer.request();
    await pumpMicrotasks();

    await refresh.complete(0, error: StateError('offline'));

    expect(refresh.calls, hasLength(2));
  });

  test('a pending request yields to an owner load started meanwhile', () async {
    coalescer.request();
    coalescer.request();
    await pumpMicrotasks();

    busy = true;
    await refresh.complete(0);
    expect(refresh.calls, hasLength(1), reason: 'deferred, not overlapping');

    busy = false;
    coalescer.settled();
    await pumpMicrotasks();
    expect(refresh.calls, hasLength(2));
  });

  test('dispose stops a pending trailing refresh and later requests', () async {
    coalescer.request();
    coalescer.request();
    await pumpMicrotasks();

    coalescer.dispose();
    await refresh.complete(0);
    coalescer.request();
    coalescer.settled();
    await pumpMicrotasks();

    expect(refresh.calls, hasLength(1));
  });
}
