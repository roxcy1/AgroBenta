import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/seller_verification.dart';
import '../../../widgets/detail_row.dart';
import '../../../widgets/notice_banner.dart';
import '../widgets/seller_verification_documents_section.dart';

/// The frame every verification status is presented in.
///
/// The **word** carries the meaning — "Under review", "Not approved" — and the
/// accent colour is only a supporting signal, so the state is still readable on a
/// greyscale screen or to someone who does not distinguish the colours. That is
/// the rule in `mobile/DESIGN.md`, and it is why a rejected application does not
/// rely on red alone to say it was rejected.
class SellerVerificationStatusCard extends StatelessWidget {
  const SellerVerificationStatusCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.body,
    this.children = const <Widget>[],
    this.action,
    super.key,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String body;

  /// Detail rows between the body and the action, e.g. the submitted date.
  final List<Widget> children;

  /// The single action offered, if this status offers one. `null` for statuses
  /// where there is nothing useful to do — being under review is not an error the
  /// user can act on, so no button appears.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon, color: accent, size: 24),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(body, style: theme.textTheme.bodySmall),
            if (children.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              ...children,
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A short reminder above the last field that the information is reviewed.
///
/// Neutral, brand-toned rather than amber: this is guidance, not a warning, and
/// it must not read as though something has already gone wrong.
class SellerVerificationAccuracyNotice extends StatelessWidget {
  const SellerVerificationAccuracyNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return const NoticeBanner(
      accent: AppColors.primary,
      icon: Icons.info_outline,
      message:
          'Please make sure your information is accurate. An administrator '
          'will review it before you can sell.',
    );
  }
}

/// The step indicator across the top of the seller application.
///
/// The reference shows four steps (Basic Information, Documents, Review,
/// Submitted). The form's editable steps are the first three; "Submitted" is a
/// terminal label that is only reached after the backend accepts the
/// application, which is why the form's own indicator never advances past
/// Review — see [SellerVerificationFormScreen].
///
/// Numbered circles carry the state as text, not colour alone: a completed step
/// shows a check, the active one its number, and a future one a muted number.
class SellerApplicationProgressIndicator extends StatelessWidget {
  const SellerApplicationProgressIndicator({
    required this.steps,
    required this.currentStep,
    super.key,
  });

  /// The step labels, in order.
  final List<String> steps;

  /// Zero-based index of the step being edited.
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < steps.length; i++) ...<Widget>[
          if (i > 0)
            Expanded(
              child: Padding(
                // Aligns the connector with the centre of the 28dp marker.
                padding: const EdgeInsets.only(top: 13),
                child: Container(
                  height: 2,
                  color: i <= currentStep
                      ? AppColors.primary
                      : AppColors.border,
                ),
              ),
            ),
          _StepMarker(
            index: i,
            label: steps[i],
            isComplete: i < currentStep,
            isActive: i == currentStep,
            theme: theme,
          ),
        ],
      ],
    );
  }
}

class _StepMarker extends StatelessWidget {
  const _StepMarker({
    required this.index,
    required this.label,
    required this.isComplete,
    required this.isActive,
    required this.theme,
  });

  final int index;
  final String label;
  final bool isComplete;
  final bool isActive;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final bool reached = isComplete || isActive;
    final Color color = reached ? AppColors.primary : AppColors.border;

    return SizedBox(
      width: 96,
      child: Column(
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: isComplete
                ? const Icon(Icons.check, size: 16, color: AppColors.surface)
                : Text(
                    '${index + 1}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: isActive
                          ? AppColors.surface
                          : AppColors.textSecondary,
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: reached ? AppColors.text : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The "Become a Seller" introduction — the first thing a buyer who has never
/// applied sees.
///
/// This is the same screen as the rest of the flow, entered at its first state:
/// the reference's separate intro is not added as a second entry point, because
/// the app already has exactly one ("Become a Seller" on the profile screen), and
/// a duplicate entry screen is what the design notes warn against.
///
/// The headline is the reference's `Start Selling on AgroBenta` (doc 01). The app
/// bar already carries `Become a Seller`, so the card must not repeat it — two
/// identical strings on one screen read as a mistake.
class SellerVerificationIntroView extends StatelessWidget {
  const SellerVerificationIntroView({required this.onStart, super.key});

  final VoidCallback onStart;

  static const List<(IconData, String)> _benefits = <(IconData, String)>[
    (Icons.add_business_outlined, 'List your livestock'),
    (Icons.verified_outlined, 'Get verified'),
    (Icons.list_alt_outlined, 'Manage your listings'),
    (Icons.forum_outlined, 'Connect with buyers'),
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SellerVerificationStatusCard(
      icon: Icons.storefront_outlined,
      accent: AppColors.primary,
      title: 'Start Selling on AgroBenta',
      body:
          'List livestock and connect with interested buyers. Your business '
          'details and identity documents go to an administrator for review '
          'before you can publish.',
      children: <Widget>[
        for (final (IconData icon, String label) in _benefits)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        Image.asset(
          'assets/images/AgroBentaLogo.png',
          height: 48,
          fit: BoxFit.contain,
        ),
        FilledButton(
          onPressed: onStart,
          child: const Text('Get Started'),
        ),
      ],
    );
  }
}

/// An application is on file and open for review — the reference's "Pending
/// Verification / Application Details" screen.
///
/// A second application is refused by the server with a `409`, so showing a form
/// here would invite the user into a dead end and then tell them off for entering
/// it. There is likewise no "Edit Application": the contract has no endpoint for
/// editing an open record, and a rejection is answered with a new submission, not
/// an edit of the old one.
class SellerVerificationAwaitingReviewView extends StatelessWidget {
  const SellerVerificationAwaitingReviewView({
    required this.verification,
    super.key,
  });

  /// The open record.
  ///
  /// Non-null: the controller only publishes [SellerVerificationUiStatus
  /// .awaitingReview] together with a record the server returned, and the screen
  /// falls back to the intro when there is no record at all.
  final SellerVerification verification;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SellerVerificationStatusCard(
          icon: Icons.hourglass_empty,
          accent: AppColors.warning,
          title: 'Under review',
          body:
              'Your application is with an administrator. You will be able to sell '
              'once it is approved. You cannot send another application while this '
              'one is being reviewed.',
          children: <Widget>[
            DetailRow(label: 'Business', value: verification.businessName),
            if (verification.businessLocation != null &&
                verification.businessLocation!.trim().isNotEmpty)
              DetailRow(
                label: 'Location',
                value: verification.businessLocation!.trim(),
              ),
            if (verification.businessDescription != null &&
                verification.businessDescription!.trim().isNotEmpty)
              DetailRow.body(verification.businessDescription!.trim()),
            if (verification.submittedAt != null)
              DetailRow(
                label: 'Submitted',
                value: AppFormatters.formatDateTime(verification.submittedAt),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SellerVerificationDocumentsSection(verification: verification),
      ],
    );
  }
}

/// Declined, with a way back in.
///
/// The only status that offers "Resubmit", matching the server: an open record
/// blocks a submission, and an approved account is refused with a `403` and never
/// offered the form. Resubmitting files a **new** application and leaves the
/// rejected one on file.
class SellerVerificationRejectedView extends StatelessWidget {
  const SellerVerificationRejectedView({
    required this.verification,
    required this.onResubmit,
    super.key,
  });

  final SellerVerification verification;
  final VoidCallback onResubmit;

  @override
  Widget build(BuildContext context) {
    return SellerVerificationStatusCard(
      icon: Icons.cancel_outlined,
      accent: AppColors.error,
      title: 'Not approved',
      body:
          'This application was not approved. You can send a new one after '
          'reviewing the reason below.',
      action: FilledButton(
        onPressed: onResubmit,
        child: const Text('Resubmit Verification'),
      ),
      children: <Widget>[
        DetailRow(label: 'Business', value: verification.businessName),
        if (verification.adminNote != null &&
            verification.adminNote!.trim().isNotEmpty)
          NoticeBanner(
            accent: AppColors.error,
            title: 'Reason given',
            message: verification.adminNote!.trim(),
            backgroundColor: AppColors.background,
          ),
        if (verification.reviewedAt != null)
          DetailRow(
            label: 'Reviewed',
            value: AppFormatters.formatDateTime(verification.reviewedAt),
          ),
      ],
    );
  }
}

/// Approved.
///
/// Reports the verification, and says plainly that seller capability comes from
/// the account — this screen does not grant it and must not imply it did. The
/// capability chip on Home is refreshed from `/auth/me` when this status is read.
class SellerVerificationApprovedView extends StatelessWidget {
  const SellerVerificationApprovedView({required this.verification, super.key});

  final SellerVerification verification;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SellerVerificationStatusCard(
          icon: Icons.verified_outlined,
          accent: AppColors.success,
          title: 'Approved — you are a seller',
          body:
              'Your seller verification was approved, so your account now has seller '
              'capability. Account type is shown on your Home screen.',
          children: <Widget>[
            DetailRow(label: 'Business', value: verification.businessName),
            if (verification.reviewedAt != null)
              DetailRow(
                label: 'Approved',
                value: AppFormatters.formatDateTime(verification.reviewedAt),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SellerVerificationDocumentsSection(verification: verification),
      ],
    );
  }
}

/// The read failed. Retryable, because almost every cause is transient.
class SellerVerificationErrorState extends StatelessWidget {
  const SellerVerificationErrorState({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Could not load your seller verification',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

/// A `409`: the application already exists.
///
/// Amber rather than red, and worded as information rather than failure. The
/// user's submission was valid; the server simply already had it. Presenting
/// this as a red error would tell them they had done something wrong at the exact
/// moment the answer is "you are already in the queue, nothing more to do".
class SellerVerificationConflictNotice extends StatelessWidget {
  const SellerVerificationConflictNotice({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return NoticeBanner(
      accent: AppColors.warning,
      icon: Icons.info_outline,
      message: message,
    );
  }
}
