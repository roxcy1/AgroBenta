import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../state/account_mode.dart';

/// The brief full-screen cover shown while the app changes Account Mode.
///
/// It is decoration only: the mode itself is switched by the controller, and the
/// change is announced to screen readers separately, so this is excluded from
/// semantics. Fading it in and out is the caller's job, which keeps this widget
/// a plain, testable layout.
class AccountModeTransitionOverlay extends StatelessWidget {
  const AccountModeTransitionOverlay({required this.mode, super.key});

  /// The mode being switched to.
  final AccountMode mode;

  /// "Seller Mode" / "Buyer Mode", as shown on the home screens and in Profile.
  static String labelFor(AccountMode mode) =>
      mode == AccountMode.seller ? 'Seller Mode' : 'Buyer Mode';

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    return ExcludeSemantics(
      child: ColoredBox(
        color: AppColors.primary,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                mode == AccountMode.seller
                    ? Icons.storefront_outlined
                    : Icons.shopping_cart_outlined,
                size: 40,
                color: Colors.white,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Switching to ${labelFor(mode)}…',
                style: textTheme.titleMedium?.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
