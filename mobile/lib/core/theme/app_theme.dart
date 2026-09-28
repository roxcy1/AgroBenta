import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// The single place the AgroBenta visual identity is expressed in Flutter.
///
/// Every widget in the app should reach for `Theme.of(context)` rather than
/// hard-coding colours, radii or text styles. If a screen needs something this
/// file does not provide, add it here instead of styling locally — that is what
/// keeps the app looking like one product.
///
/// This theme is deliberately restrained. It uses borders and small shadows for
/// depth rather than heavy elevation, and it avoids glassmorphism, neon, large
/// gradients and decorative animation. See `mobile/DESIGN.md`.
abstract final class AppTheme {
  /// Build the light theme. The app is light-only for now; a dark theme is a
  /// separate decision and should not be introduced incidentally.
  static ThemeData light() {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.primaryLight,
      onSecondary: Colors.white,
      error: AppColors.error,
      onError: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      outline: AppColors.border,
      outlineVariant: AppColors.border,
    );

    const TextTheme textTheme = _textTheme;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      dividerColor: AppColors.border,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: AppSizes.appBarHeight,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),

      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        // Labels stay visible above the field. Never hide a label inside a
        // placeholder — placeholders disappear the moment a user types.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(AppSizes.controlHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: textTheme.titleSmall,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(AppSizes.controlHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: textTheme.titleSmall,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: textTheme.titleSmall,
        ),
      ),

      // Restrained status chips. Shape is moderate, not fully pill-like, and
      // colour is supplied per-status via StatusChip.
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.border),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.text,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xxs,
        ),
        minVerticalPadding: AppSpacing.sm,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),

      // The bottom navigation bar, introduced with the buyer shell.
      //
      // The indicator defaults to the seed colour's `secondaryContainer`, which
      // renders as a pale sage and fights the brand green, so it is pinned to
      // [AppColors.primary]. That fixes the icon colours too: in Material 3 the
      // selected icon sits *inside* the indicator pill and its label sits
      // outside it, so the icon must be white-on-green while the label is
      // green-on-surface. Making the selected icon the same green as the pill
      // would hide it completely.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
          (Set<WidgetState> states) => _textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textSecondary,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
          (Set<WidgetState> states) => IconThemeData(
            // On the indicator: white. Off it: the secondary text colour.
            color: states.contains(WidgetState.selected)
                ? Colors.white
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// Mobile type scale.
  ///
  /// This is a deliberate, documented adaptation of the type scale in the root
  /// `DESIGN.md` (§4), not a replacement of it. The web scale bottoms out at a
  /// 14px body; on a phone, held at arm's length in daylight, 14px is at the
  /// low end of comfortable. Body text is therefore 15px and secondary text is
  /// 13px, while the page-title and section-heading sizes are kept identical to
  /// the web so the two products still read as the same system.
  ///
  /// Font family is deliberately unset: Flutter uses the platform UI font
  /// (Roboto on Android, SF on iOS), which is the mobile equivalent of the
  /// "conventional professional system font" the root `DESIGN.md` requires. Do
  /// not add a bundled or downloaded display font.
  static const TextTheme _textTheme = TextTheme(
    // Page title — matches web 24–28px band, at the lower bound for mobile.
    headlineSmall: TextStyle(
      fontSize: 24,
      height: 1.25,
      fontWeight: FontWeight.w600,
      color: AppColors.text,
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      height: 1.25,
      fontWeight: FontWeight.w600,
      color: AppColors.text,
    ),

    // Section heading — matches web 16–18px band.
    titleLarge: TextStyle(
      fontSize: 18,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: AppColors.text,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: AppColors.text,
    ),

    // Card title / list item title.
    titleSmall: TextStyle(
      fontSize: 14,
      height: 1.4,
      fontWeight: FontWeight.w600,
      color: AppColors.text,
    ),

    // Body.
    bodyLarge: TextStyle(
      fontSize: 16,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: AppColors.text,
    ),
    bodyMedium: TextStyle(
      fontSize: 15,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: AppColors.text,
    ),

    // Secondary text — matches web 12–13px band, at the upper bound.
    bodySmall: TextStyle(
      fontSize: 13,
      height: 1.45,
      fontWeight: FontWeight.w400,
      color: AppColors.textSecondary,
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      height: 1.35,
      fontWeight: FontWeight.w500,
      color: AppColors.textSecondary,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      height: 1.35,
      fontWeight: FontWeight.w500,
      color: AppColors.textSecondary,
    ),
  );
}
