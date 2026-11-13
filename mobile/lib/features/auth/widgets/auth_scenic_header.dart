import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../widgets/temporary_logo.dart';

/// The brand header at the top of the sign-in, registration and profile
/// screens.
///
/// A plain white band with the AgroBenta logo and tagline. The logo artwork
/// already carries the "AgroBenta" wordmark, so the name is not repeated as
/// text; the logo's semantics label still announces it. The painted sky and
/// hills that used to sit behind it were dropped for a calmer, more
/// professional first screen.
///
/// This is presentation only. It holds no state and knows nothing about the
/// form or the API, exactly like the rest of the auth widgets.
class AuthScenicHeader extends StatelessWidget {
  const AuthScenicHeader({required this.height, super.key});

  /// Height of the band.
  ///
  /// The caller derives it from the viewport and the current text scale so the
  /// brand block cannot overflow when the user has enlarged text.
  final double height;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double logoHeight = (height * 0.62).clamp(56.0, 130.0);

    return Container(
      height: height,
      width: double.infinity,
      color: AppColors.surface,
      // Centred in the band, so the brand sits close to the form below it
      // rather than floating at the top with a gap underneath.
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TemporaryLogo(size: logoHeight),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Buy. Sell. Grow. Together.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
