import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// The shared layout for the sign-in and registration forms.
///
/// The brand wordmark and tagline sit above the form, then a screen heading,
/// then the fields in one card on a light background under a green app bar —
/// the same shape the placeholder screen used and the same shape every other
/// AgroBenta screen will use. The form scrolls and respects the safe area, so
/// the fields stay reachable with the keyboard open and the layout survives a
/// 200% text scale.
class AuthFormScaffold extends StatelessWidget {
  const AuthFormScaffold({
    required this.title,
    required this.heading,
    required this.fields,
    this.submitLabel,
    this.isSubmitting = false,
    this.onSubmit,
    this.footer,
    super.key,
  });

  /// App bar title.
  final String title;

  /// The one thing this screen is for, stated above the form.
  final String heading;

  /// The form controls, in order.
  final List<Widget> fields;

  /// The verb on the primary button. Null hides the button, for the states
  /// where there is nothing to submit.
  final String? submitLabel;

  /// Whether a request is in flight. The button is disabled so a tap cannot
  /// fire twice, and shows a spinner instead of its label.
  final bool isSubmitting;

  final VoidCallback? onSubmit;

  /// The alternative action, below the button.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Center(
            child: ConstrainedBox(
              // A phone is narrower than this, so the constraint only matters
              // on a tablet or in landscape, where it stops the form stretching
              // into unreadable full-width fields.
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const _AuthBrandHeader(),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        heading,
                        style: theme.textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      ...fields,
                      if (submitLabel != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.xl),
                        FilledButton(
                          onPressed: isSubmitting ? null : onSubmit,
                          child: isSubmitting
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(submitLabel!),
                        ),
                      ],
                      if (footer != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        footer!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The AgroBenta wordmark and tagline, centred above the form.
///
/// The app has no logo asset yet, so the wordmark is rendered directly in the
/// brand green using the same scale the app bar titles use. The tagline is the
/// one from `mobile/DESIGN.md` §11.1.
class _AuthBrandHeader extends StatelessWidget {
  const _AuthBrandHeader();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      children: <Widget>[
        Text(
          'AgroBenta',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Buy. Sell. Grow. Together.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
