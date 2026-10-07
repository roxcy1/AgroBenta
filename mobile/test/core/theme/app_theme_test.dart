import 'package:agrobenta_mobile/core/theme/app_colors.dart';
import 'package:agrobenta_mobile/core/theme/app_spacing.dart';
import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ThemeData theme = AppTheme.light();

  group('palette', () {
    test('primary is the AgroBenta brand green', () {
      // #006B4F — the dark agricultural green in `mobile/DESIGN.md` §3.
      expect(AppColors.primary, const Color(0xFF006B4F));
    });

    test('exposes every semantic token the design system requires', () {
      expect(AppColors.primary, isA<Color>());
      expect(AppColors.primaryLight, isA<Color>());
      expect(AppColors.primaryDark, isA<Color>());
      expect(AppColors.primarySurface, isA<Color>());
      expect(AppColors.background, isA<Color>());
      expect(AppColors.surface, isA<Color>());
      expect(AppColors.text, isA<Color>());
      expect(AppColors.textSecondary, isA<Color>());
      expect(AppColors.border, isA<Color>());
      expect(AppColors.success, isA<Color>());
      expect(AppColors.warning, isA<Color>());
      expect(AppColors.error, isA<Color>());
    });

    test('keeps text readable against the background', () {
      // Guards against a future palette tweak silently destroying contrast.
      expect(
        ThemeData.estimateBrightnessForColor(AppColors.text),
        Brightness.dark,
      );
      expect(
        ThemeData.estimateBrightnessForColor(AppColors.background),
        Brightness.light,
      );
    });

    test('uses white for on-brand surfaces', () {
      expect(
        AppColors.primary.computeLuminance(),
        lessThan(AppColors.surface.computeLuminance()),
      );
    });
  });

  group('theme', () {
    test('applies the brand colour scheme', () {
      expect(theme.colorScheme.primary, AppColors.primary);
      expect(theme.colorScheme.onPrimary, Colors.white);
      expect(theme.colorScheme.error, AppColors.error);
      expect(theme.colorScheme.surface, AppColors.surface);
    });

    test('uses the neutral background for scaffolds', () {
      expect(theme.scaffoldBackgroundColor, AppColors.background);
    });

    test('uses a solid brand app bar with no elevation', () {
      expect(theme.appBarTheme.backgroundColor, AppColors.primary);
      expect(theme.appBarTheme.elevation, 0);
      expect(theme.appBarTheme.foregroundColor, Colors.white);
    });

    test('cards use a border and a moderate radius, not heavy elevation', () {
      final CardThemeData card = theme.cardTheme;

      expect(card.elevation, 0);
      expect(
        card.shape,
        isA<RoundedRectangleBorder>().having(
          (RoundedRectangleBorder shape) => shape.borderRadius,
          'borderRadius',
          BorderRadius.circular(AppRadius.lg),
        ),
      );
    });

    test('app bar height and control height are standardised', () {
      expect(theme.appBarTheme.toolbarHeight, AppSizes.appBarHeight);
      expect(AppSizes.minTouchTarget, greaterThanOrEqualTo(48));
      expect(AppSizes.controlHeight, greaterThanOrEqualTo(48));
    });

    test('input labels always float so they are never placeholder-only', () {
      expect(
        theme.inputDecorationTheme.floatingLabelBehavior,
        FloatingLabelBehavior.always,
      );
    });

    test('primary buttons use the brand green and a full control height', () {
      final ButtonStyle style = theme.filledButtonTheme.style!;

      expect(
        style.backgroundColor?.resolve(<WidgetState>{}),
        AppColors.primary,
      );
      expect(
        style.minimumSize?.resolve(<WidgetState>{}),
        const Size.fromHeight(AppSizes.controlHeight),
      );
    });

    test('uses the platform system font, with no bundled display font', () {
      // Root DESIGN.md §4 requires a conventional system font. The theme must
      // not override Flutter's platform default (Roboto on Android, SF on
      // iOS), and `pubspec.yaml` declares no `fonts:` block.
      expect(
        theme.textTheme.bodyMedium?.fontFamily,
        ThemeData.light().textTheme.bodyMedium?.fontFamily,
      );
    });
  });

  group('type scale', () {
    test('keeps screen titles in the 18-20sp band from mobile DESIGN.md', () {
      expect(theme.textTheme.headlineSmall?.fontSize, inInclusiveRange(18, 20));
      expect(
        theme.textTheme.headlineMedium?.fontSize,
        inInclusiveRange(18, 20),
      );
    });

    test('keeps section headings in the 15-17sp band', () {
      expect(theme.textTheme.titleLarge?.fontSize, inInclusiveRange(15, 17));
      expect(theme.textTheme.titleMedium?.fontSize, inInclusiveRange(15, 17));
    });

    test('does not make all text bold', () {
      expect(theme.textTheme.bodyMedium?.fontWeight, FontWeight.w400);
      expect(theme.textTheme.bodySmall?.fontWeight, FontWeight.w400);
    });
  });
}
