import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// The Home screen's hero banner.
///
/// The project ships no approved banner asset — `pubspec.yaml` registers no
/// images and the only PNGs on disk are platform launcher icons — so per the
/// approved design (`AgroBenta_Home_DESIGN (1).md` §3.3) this is a restrained
/// branded placeholder: the same painted rolling-hills landscape the auth
/// screens use, with the marketing copy and the single green CTA on top. When
/// a real banner asset lands, only this widget's background changes.
///
/// No carousel, no indicators: there is one static banner and nothing to swipe
/// between. The CTA is the marketplace destination the design names.
class HomeHeroBanner extends StatelessWidget {
  const HomeHeroBanner({this.onExplore, super.key});

  /// Switches the shell to the Marketplace tab. Null omits the button, so a
  /// standalone use of this screen never renders a dead CTA.
  final VoidCallback? onExplore;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenGutter),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 160),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Stack(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Quality Livestock for a Better Tomorrow',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(
                        'Connect with trusted sellers and grow your '
                        'opportunities.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (onExplore != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      // Compact, as in the approved design: the banner is
                      // an invitation, not the screen's main action.
                      FilledButton(
                        onPressed: onExplore,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          tapTargetSize: MaterialTapTargetSize.padded,
                        ),
                        child: const Text('Explore Now'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
