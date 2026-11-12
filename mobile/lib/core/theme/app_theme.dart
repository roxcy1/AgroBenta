import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_input_border.dart';
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
  /// The bundled UI typeface, registered in `pubspec.yaml`.
  static const String fontFamily = 'PublicSans';

  static ThemeData light() {
    final ColorScheme colorScheme =
        ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
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
      // Public Sans, bundled in assets/fonts (mobile/DESIGN.md §4).
      fontFamily: fontFamily,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      dividerColor: AppColors.border,
      splashFactory: InkSparkle.splashFactory,

      // White app bars with a hairline underneath. Brand green is kept for
      // actions, the selected tab and prices, so a solid green bar on every
      // screen no longer competes with them.
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: AppSizes.appBarHeight,
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: AppColors.text,
          fontWeight: FontWeight.w600,
        ),
      ),

      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      // Modals use the mobile design's recommended elevations and radii rather
      // than Material's defaults, which tint from the seed colour.
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),

      // The one floating action (Create listing) is a solid brand-green
      // button with white text, as in the approved design, not the seed's
      // pale tonal container.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 2,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        extendedTextStyle: _textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      // Text fields, per the approved design: the label sits above a 46dp
      // white box with a 1dp outline that turns brand green and 2dp thick on
      // focus. See `LabelAboveInputBorder` for how the label is kept above
      // the box rather than in a notch.
      inputDecorationTheme: InputDecorationTheme(
        // The border paints the box's fill itself, below the label band.
        filled: false,
        // Labels stay visible above the field. Never hide a label inside a
        // placeholder — placeholders disappear the moment a user types.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        // For a field with a label. A field without one passes
        // `AppInputs.plainPadding`.
        contentPadding: AppInputs.labelledPadding,
        // Never drawn: its size only sets the gap from the label to the
        // text. See `AppInputs.inlineLabelFontSize`.
        labelStyle: const TextStyle(
          fontSize: AppInputs.inlineLabelFontSize,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
        // Drawn at 0.75 scale by Material, so this reads as 13.
        floatingLabelStyle: const TextStyle(
          fontSize: AppInputs.labelFontSize / AppInputs.floatingLabelScale,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: AppColors.textHint),
        helperStyle: textTheme.labelMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
        errorStyle: textTheme.labelMedium?.copyWith(color: AppColors.error),
        errorMaxLines: 3,
        prefixIconColor: AppColors.textHint,
        suffixIconColor: AppColors.textHint,
        // 40, not Material's 48, so an icon never makes the 46dp box taller.
        prefixIconConstraints: const BoxConstraints(
          minWidth: AppInputs.iconSlotWidth,
          minHeight: 40,
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: AppInputs.iconSlotWidth,
          minHeight: 40,
        ),
        border: const LabelAboveInputBorder(),
        enabledBorder: const LabelAboveInputBorder(),
        disabledBorder: const LabelAboveInputBorder(
          borderSide: BorderSide(color: AppColors.border),
          fillColor: AppColors.background,
        ),
        focusedBorder: const LabelAboveInputBorder(
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: const LabelAboveInputBorder(
          borderSide: BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: const LabelAboveInputBorder(
          borderSide: BorderSide(color: AppColors.error, width: 2),
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
      // The selected tab is marked by a thin green line and green icon and
      // label, so it reads clearly without being the loudest thing on screen.
      // The seed's default `secondaryContainer` (a pale sage) is not used.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        // No filled pill: the selected tab gets a short brand-green line
        // above its icon and a green icon and label.
        indicatorColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorShape: const Border(
          top: BorderSide(color: AppColors.primary, width: 3),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
          (Set<WidgetState> states) => _textTheme.labelMedium?.copyWith(
            // 11, not the 12 of labelMedium: with five tabs on a 375-wide
            // phone, a semibold "Transactions" at 12 wraps mid-word.
            fontSize: 11,
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
            // The proposal draws the tab glyphs at 22, not Material's 24.
            size: 22,
            // Selected: brand green. Otherwise: secondary text.
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// Mobile type scale, per `mobile/DESIGN.md` §4.
  ///
  /// The mobile design has its own compact hierarchy (18–20sp screen titles,
  /// 15–17sp section headings, 13–15sp body) that is deliberately smaller than
  /// the root `DESIGN.md`'s web scale. On a phone a 24–28px heading consumes
  /// most of the screen; the prototype keeps titles restrained so content and
  /// livestock imagery stay dominant.
  ///
  /// The family is applied once, on [ThemeData.fontFamily]: Public Sans, the
  /// single approved UI typeface. Do not add a second, display font.
  static const TextTheme _textTheme = TextTheme(
    // Brand title - the AgroBenta wordmark on the sign-in and register headers.
    // The only large style; no screen title uses it.
    displaySmall: TextStyle(
      fontSize: 28,
      height: 1.2,
      fontWeight: FontWeight.w800,
      color: AppColors.text,
    ),

    // Screen title — 18–20sp bold. Top of the band keeps it present without
    // swallowing the screen.
    headlineMedium: TextStyle(
      fontSize: 20,
      height: 1.3,
      fontWeight: FontWeight.w700,
      color: AppColors.text,
    ),
    headlineSmall: TextStyle(
      fontSize: 19,
      height: 1.3,
      fontWeight: FontWeight.w700,
      color: AppColors.text,
    ),

    // Section heading — 15–17sp semibold.
    titleLarge: TextStyle(
      fontSize: 17,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: AppColors.text,
    ),
    titleMedium: TextStyle(
      fontSize: 15,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: AppColors.text,
    ),

    // Card title — 14–16sp semibold.
    titleSmall: TextStyle(
      fontSize: 14,
      height: 1.4,
      fontWeight: FontWeight.w600,
      color: AppColors.text,
    ),

    // Body — 13–15sp regular.
    bodyLarge: TextStyle(
      fontSize: 15,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: AppColors.text,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: AppColors.text,
    ),

    // Secondary — 11–13sp regular. Supporting copy is lighter than primary.
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
