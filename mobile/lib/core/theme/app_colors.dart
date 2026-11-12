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

  /// Primary brand green. Primary buttons, the selected tab, links, prices
  /// and important actions. App bars are white, not green. (`#1B5E20`)
  static const Color primary = Color(0xFF1B5E20);

  /// Primary-action green ("marketplace green"). Brighter accent used for
  /// pressed/hovered brand states and tonal highlights. (`#2E7D32`)
  static const Color primaryLight = Color(0xFF2E7D32);

  /// Darkest brand green — the "dark header" deep green, for header bands and
  /// brand surfaces that must read darker than [primary]. (`#134417`)
  static const Color primaryDark = Color(0xFF134417);

  /// Very light green surface. Information panels, selected/active surfaces,
  /// seller-related highlights and AI suggestion backgrounds. (`#EAF2E8`)
  static const Color primarySurface = Color(0xFFEAF2E8);

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

  /// Success, and semantically "approved / active / completed". (`#2E7D32`)
  static const Color success = Color(0xFF2E7D32);

  /// "sold" status, blue. (`#1D5385`)
  static const Color sold = Color(0xFF1D5385);

  /// Warning, and semantically "pending / awaiting review". (`#8A5A00`)
  static const Color warning = Color(0xFF8A5A00);

  /// Very light amber surface for a pending/awaiting status panel. The
  /// counterpart to [primarySurface] for [warning]: the Inquiry Sent screen's
  /// status card needs a pale amber that pairs with the amber clock icon, and
  /// tinting [warning] itself would put body text below contrast. (`#FBF0D9`)
  static const Color warningSurface = Color(0xFFFBF0D9);

  /// Error, and semantically "rejected / failed / invalid". (`#A3302A`)
  static const Color error = Color(0xFFA3302A);

  // --- Surfaces ------------------------------------------------------------

  /// Screen background. Light neutral, not white, so cards can sit on top.
  static const Color background = Color(0xFFF5F6F4);

  /// Card, sheet and dialog surface.
  static const Color surface = Color(0xFFFFFFFF);

  /// Hairline borders and dividers. Prefer this over shadows for separation.
  static const Color border = Color(0xFFE2E6E0);

  /// A text field's outline. A step darker than [border] so an empty field
  /// still reads as a control on a white page. (`#CFD8CA`)
  static const Color fieldBorder = Color(0xFFCFD8CA);

  // --- Text ----------------------------------------------------------------

  /// Primary body and heading text.
  static const Color text = Color(0xFF16241A);

  /// Secondary text: captions, helper copy, metadata.
  static const Color textSecondary = Color(0xFF5B665E);

  /// Placeholder text and the small icons inside a text field. Lighter than
  /// [textSecondary]; never used for copy a user has to read. (`#8B948D`)
  static const Color textHint = Color(0xFF8B948D);
}
