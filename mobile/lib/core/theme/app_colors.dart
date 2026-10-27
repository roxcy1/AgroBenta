import 'package:flutter/material.dart';

/// Canonical AgroBenta colour palette.
///
/// The hex values are the mobile design targets in `mobile/DESIGN.md` §3.
/// They are intentionally **not** a mirror of the Admin Web tokens in
/// `frontend/src/index.css`: the web palette uses darker, Material-derived
/// greens, while this list is the approved mobile prototype palette. Keeping
/// the two aligned in accent and proportion is what makes the products read as
/// one system; the exact values differ by platform.
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

  /// Primary brand green. App bars, primary buttons, selected navigation,
  /// links and important actions. (`#006B4F`)
  static const Color primary = Color(0xFF006B4F);

  /// Primary-action green ("marketplace green"). Brighter accent used for
  /// pressed/hovered brand states and tonal highlights. (`#008A5A`)
  static const Color primaryLight = Color(0xFF008A5A);

  /// Darkest brand green — the "dark header" deep green, for header bands and
  /// brand surfaces that must read darker than [primary]. (`#005A43`)
  static const Color primaryDark = Color(0xFF005A43);

  /// Very light green surface. Information panels, selected/active surfaces,
  /// seller-related highlights and AI suggestion backgrounds. (`#EAF7F0`)
  static const Color primarySurface = Color(0xFFEAF7F0);

  // --- Illustration (auth hero) -------------------------------------------
  //
  // The registration hero is a code-drawn landscape — the project has no brand
  // scenery asset yet — so these are the only two tones it needs beyond the
  // brand greens (which it reuses for the hills) and white (clouds and sun).
  // They are illustration-only: not UI surfaces, not brand accents. They live
  // here rather than as literals in the widget so the whole palette still has
  // exactly one home.

  /// Top of the registration hero sky gradient. (`#BEE3F5`)
  static const Color skyTop = Color(0xFFBEE3F5);

  /// Bottom of the registration hero sky gradient, near the horizon.
  /// (`#EDF6FC`)
  static const Color skyBottom = Color(0xFFEDF6FC);

  // --- Semantic status -----------------------------------------------------

  /// Success, and semantically "approved / active / completed". (`#168A4A`)
  static const Color success = Color(0xFF168A4A);

  /// "sold" status, blue. (`#1565C0`)
  static const Color sold = Color(0xFF1565C0);

  /// Warning, and semantically "pending / awaiting review". (`#D98B00`)
  static const Color warning = Color(0xFFD98B00);

  /// Very light amber surface for a pending/awaiting status panel. The
  /// counterpart to [primarySurface] for [warning]: the Inquiry Sent screen's
  /// status card needs a pale amber that pairs with the amber clock icon, and
  /// tinting [warning] itself would put body text below contrast. (`#FDF3E3`)
  static const Color warningSurface = Color(0xFFFDF3E3);

  /// Error, and semantically "rejected / failed / invalid". (`#C93636`)
  static const Color error = Color(0xFFC93636);

  // --- Surfaces ------------------------------------------------------------

  /// Screen background. Light neutral, not white, so cards can sit on top.
  static const Color background = Color(0xFFF7F8F7);

  /// Card, sheet and dialog surface.
  static const Color surface = Color(0xFFFFFFFF);

  /// Hairline borders and dividers. Prefer this over shadows for separation.
  static const Color border = Color(0xFFD9DEE3);

  // --- Text ----------------------------------------------------------------

  /// Primary body and heading text.
  static const Color text = Color(0xFF202124);

  /// Secondary text: captions, helper copy, metadata.
  static const Color textSecondary = Color(0xFF6B7280);
}
