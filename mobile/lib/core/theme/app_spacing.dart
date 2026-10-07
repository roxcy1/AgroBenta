/// Spacing, radius and sizing tokens.
///
/// The goal is that every gap in the app is one of these values, so that
/// vertical rhythm stays consistent across screens built by different people
/// in different phases.
abstract final class AppSpacing {
  /// 4dp — icon-to-label gaps, badge padding.
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
/// AgroBenta uses moderate radius. Do not make cards excessively rounded, and
/// do not reach for fully circular pills except for genuine status chips.
abstract final class AppRadius {
  /// 8dp — inputs, primary/secondary buttons, chips. (DESIGN: fields and
  /// buttons 8–10.)
  static const double sm = 8;

  /// 10dp — list tiles, image containers, the navigation indicator. (DESIGN:
  /// image containers 10–12.)
  static const double md = 10;

  /// 12dp — cards. This is the default for surfaces. (DESIGN: cards 10–12.)
  static const double lg = 12;

  /// 16dp — dialogs and bottom sheets. (DESIGN: dialogs 12–16.)
  static const double xl = 16;
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
