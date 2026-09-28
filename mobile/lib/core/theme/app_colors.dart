import 'package:flutter/material.dart';

/// Canonical AgroBenta colour palette.
///
/// Every value here is a 1:1 mirror of a design token that already exists in
/// `frontend/src/index.css` (`:root`). Keeping the two in sync is what makes the
/// Admin Web and this app read as one product rather than two.
///
/// Rules for using this palette:
///  * Do not add ad-hoc `Color(0xFF...)` literals in feature code. If a new
///    colour is genuinely required, add it here and document why.
///  * Do not grow this into a large colour system. The list below is
///    deliberately small.
///  * Semantic status colours (`success` / `warning` / `error`) must stay
///    restrained and meaningful. Never use them decoratively.
///
/// See `mobile/DESIGN.md` for the rules that govern how these are applied.
abstract final class AppColors {
  // --- Brand ---------------------------------------------------------------

  /// Primary brand green. The main identity and accent colour of AgroBenta.
  static const Color primary = Color(0xFF1B5E20);

  /// Lighter brand green. Used for pressed/hovered states and tonal surfaces
  /// derived from [primary].
  static const Color primaryLight = Color(0xFF2E7D32);

  /// Darkest brand green. Used for pressed states and for text/icons that must
  /// sit on a light brand surface.
  static const Color primaryDark = Color(0xFF0D3B12);

  // --- Semantic status -----------------------------------------------------

  /// Success, and semantically "approved / active / completed".
  static const Color success = Color(0xFF2E7D32);

  /// Warning, and semantically "pending / awaiting review".
  static const Color warning = Color(0xFFF57F17);

  /// Error, and semantically "rejected / failed / invalid".
  static const Color error = Color(0xFFC62828);

  // --- Surfaces ------------------------------------------------------------

  /// Screen background. Light neutral, not white, so cards can sit on top.
  static const Color background = Color(0xFFF5F5F5);

  /// Card, sheet and dialog surface.
  static const Color surface = Color(0xFFFFFFFF);

  /// Hairline borders and dividers. Prefer this over shadows for separation.
  static const Color border = Color(0xFFE0E0E0);

  // --- Text ----------------------------------------------------------------

  /// Primary body and heading text.
  static const Color text = Color(0xFF1A1A1A);

  /// Secondary text: captions, helper copy, metadata.
  static const Color textSecondary = Color(0xFF666666);
}
