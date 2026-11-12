import 'package:flutter/widgets.dart';

import '../../../repositories/trinidad_location_repository.dart';
import 'trinidad_location_controller.dart';

class TrinidadLocationScope extends InheritedWidget {
  const TrinidadLocationScope({
    required this.repository,
    required this.controller,
    required super.child,
    super.key,
  });

  final TrinidadLocationRepository repository;
  final TrinidadLocationController controller;

  static TrinidadLocationController readOf(BuildContext context) {
    final TrinidadLocationScope? scope = context
        .getInheritedWidgetOfExactType<TrinidadLocationScope>();
    assert(scope != null, 'No TrinidadLocationScope found in context.');
    return scope!.controller;
  }

  static TrinidadLocationController of(BuildContext context) {
    final TrinidadLocationScope? scope = context
        .dependOnInheritedWidgetOfExactType<TrinidadLocationScope>();
    assert(scope != null, 'No TrinidadLocationScope found in context.');
    return scope!.controller;
  }

  @override
  bool updateShouldNotify(TrinidadLocationScope oldWidget) =>
      repository != oldWidget.repository || controller != oldWidget.controller;
}
