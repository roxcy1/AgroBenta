/// Spacing, radius and sizing tokens.
///
/// The goal is that every gap in the app is one of these values, so that
/// vertical rhythm stays consistent across screens built by different people
/// in different phases.
abstract final class AppSpacing {
  /// 4dp — icon-to-label gaps, badge padding.
  /// Hairline offsets - a 2px nudge between a label and its neighbour.
  static const double xxxs = 2;
  static const double xxs = 4;

  /// 8dp — gap between tightly related elements (label to field).
  static const double xs = 8;

  /// 12dp — default gap between related elements, list item padding.
  static const double sm = 12;

  /// 16dp — the workhorse gap. Card internal padding, screen gutter.
  static const double md = 16;

  /// 20dp — padding between grouped blocks.
  static const double lg = 20;

  /// 24dp — separation between distinct sections.
  static const double xl = 24;

  /// 32dp — separation between major page regions.
  static const double xxl = 32;

  /// Horizontal screen gutter. Use this for the outermost padding of a screen.
  static const double screenGutter = 16;
}

/// Corner radius tokens.
///
/// The professional theme uses one moderate 8dp radius for fields, buttons,
/// chips and cards (mobile/DESIGN.md §6). Do not use fully circular pills.
abstract final class AppRadius {
  /// 8dp — inputs, primary/secondary buttons, chips. (DESIGN: fields and
  /// buttons 8–10.)
  static const double sm = 8;

  /// 8dp — list tiles, image containers, the navigation indicator.
  static const double md = 8;

  /// 8dp — cards. Same as every other surface in the professional theme.
  static const double lg = 8;

  /// 12dp — dialogs and bottom sheets. (DESIGN: dialogs 12–16.)
  static const double xl = 12;
}

/// Sizing tokens.
abstract final class AppSizes {
  /// Minimum interactive target. Applies to icon buttons and any tappable row.
  ///
  /// This is the Material accessibility floor. Never ship a tappable area
  /// smaller than this, even if the visible icon looks smaller.
  static const double minTouchTarget = 48;

  /// Standard height for text inputs and buttons. Keep this consistent so
  /// forms feel uniform.
  static const double controlHeight = 48;

  /// Height of the persistent app bar.
  static const double appBarHeight = 56;

  /// Corner radius for a circular avatar, used to derive avatar diameters.
  static const double circular = 1000;
}
