import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../widgets/rolling_hills_painter.dart';
import '../../../widgets/temporary_logo.dart';

/// The branded landscape header at the top of the registration screen.
///
/// The landscape is painted (sky, sun, clouds and rolling hills) and the brand
/// is the existing logo asset ([TemporaryLogo]) plus the wordmark and tagline.
///
/// This is presentation only. It holds no state and knows nothing about the
/// form or the API, exactly like the rest of the auth widgets.
class AuthScenicHeader extends StatelessWidget {
  const AuthScenicHeader({required this.height, super.key});

  /// Height of the hero band.
  ///
  /// The caller derives it from the viewport and the current text scale so the
  /// brand block above cannot overflow a fixed-height decoration when the user
  /// has enlarged text.
  final double height;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const CustomPaint(painter: RollingHillsPainter()),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(
                top: height * 0.10,
                left: AppSpacing.lg,
                right: AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const TemporaryLogo(size: 80),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'AgroBenta',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Buy. Sell. Grow. Together.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
