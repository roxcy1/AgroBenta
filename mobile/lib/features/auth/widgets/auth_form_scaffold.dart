import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';

/// The shared layout for the sign-in and registration forms.
///
/// One card on a light background under a green app bar, which is the same
/// shape the placeholder screen used and the same shape every other AgroBenta
/// screen will use. The form scrolls and respects the safe area, so the fields
/// stay reachable with the keyboard open and the layout survives a 200% text
/// scale.
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
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(heading, style: theme.textTheme.titleLarge),
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
