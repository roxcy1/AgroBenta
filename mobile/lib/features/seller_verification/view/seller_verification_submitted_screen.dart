import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/seller_verification.dart';
import '../../../widgets/detail_row.dart';
import '../../../widgets/notice_banner.dart';
import '../../../widgets/section_card.dart';
import '../state/seller_verification_controller.dart';
import '../state/seller_verification_scope.dart';

/// The confirmation shown once the backend has accepted an application.
///
/// It is pushed **only** from a successful [SellerVerificationController.submit],
/// so it never reports success for a request that failed or never left the
/// device. The status and date it shows are read from the record the server
/// returned, not invented.
///
/// "Back to Profile" pops to the first route, which is the app shell. The tab
/// stays where the flow was entered — the profile tab — so the user lands on the
/// screen they started from.
class SellerVerificationSubmittedScreen extends StatelessWidget {
  const SellerVerificationSubmittedScreen({super.key});

  static const List<String> _nextSteps = <String>[
    'An administrator reviews your application.',
    'If it is approved, your account becomes a seller account.',
    'You can then list livestock and manage your listings.',
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SellerVerificationController controller =
        SellerVerificationScope.readOf(context);
    final SellerVerification? verification = controller.state.verification;

    return Scaffold(
      appBar: AppBar(title: const Text('Seller Application')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          children: <Widget>[
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SizedBox(height: AppSpacing.xl),
                    const Icon(
                      Icons.check_circle_outline,
                      size: 64,
                      color: AppColors.success,
                    ),
                    const SizedBox(height: AppSpacing.md),
                     Image.asset(
                       'assets/images/AgroBentaLogo.png',
                       height: 48,
                       fit: BoxFit.contain,
                     ),
                     const SizedBox(height: AppSpacing.md),
                     Text(
                       'Application Submitted!',
                       textAlign: TextAlign.center,
                       style: theme.textTheme.headlineSmall,
                     ),
                     const SizedBox(height: AppSpacing.xs),
                     Text(
                       'Your application has been received and is now under '
                       'review.',
                       textAlign: TextAlign.center,
                       style: theme.textTheme.bodyMedium?.copyWith(
                         color: AppColors.textSecondary,
                       ),
                     ),
                     const SizedBox(height: AppSpacing.xl),
                    const NoticeBanner(
                      accent: AppColors.warning,
                      icon: Icons.hourglass_empty,
                      title: 'Pending verification',
                      message:
                          'An administrator will review your application. You '
                          'cannot send another one while this is open.',
                    ),
                    if (verification?.submittedAt != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      DetailRow(
                        label: 'Submitted',
                        value: AppFormatters.formatDateTime(
                          verification!.submittedAt,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    SectionCard(
                      title: 'What happens next?',
                      children: <Widget>[
                        for (int i = 0; i < _nextSteps.length; i++)
                          _NextStep(
                            number: i + 1,
                            text: _nextSteps[i],
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    FilledButton(
                      onPressed: () => Navigator.of(context).popUntil(
                        (Route<dynamic> route) => route.isFirst,
                      ),
                      child: const Text('Back to Profile'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextStep extends StatelessWidget {
  const _NextStep({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.surface,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(text, style: theme.textTheme.bodyMedium),
            ),
          ),
        ],
      ),
    );
  }
}
