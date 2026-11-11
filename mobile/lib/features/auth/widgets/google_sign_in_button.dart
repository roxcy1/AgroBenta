import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme/app_spacing.dart';

/// "Continue with Google", shared by the sign-in and registration screens.
///
/// Google sign-in both signs in an existing account and creates a buyer
/// account for a new email, so one button serves both screens. Facebook was
/// removed by project decision (MS-11, 2026-11-10).
///
/// The Google mark keeps Google's brand blue; it is the provider's identity,
/// not part of the AgroBenta palette, so it stays local to this widget.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({required this.onPressed, super.key});

  /// Null while another authentication request is running.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FaIcon(FontAwesomeIcons.google, size: 18, color: Color(0xFF4285F4)),
          SizedBox(width: AppSpacing.xs),
          Text('Continue with Google'),
        ],
      ),
    );
  }
}
