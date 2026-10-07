import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/seller_verification.dart';
import '../../../widgets/detail_row.dart';
import '../../../widgets/notice_banner.dart';

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

/// The administrator's note on a rejected application.
///
/// Quoted rather than paraphrased, and omitted entirely when there is none —
/// [SellerVerification.adminNote] being `null` is normal, and inventing a reason
/// would be inventing a decision nobody made.

/// Never applied. The entry point into the flow.
class SellerVerificationNotSubmittedView extends StatelessWidget {
  const SellerVerificationNotSubmittedView({required this.onStart, super.key});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return SellerVerificationStatusCard(
      icon: Icons.storefront_outlined,
      accent: AppColors.primary,
      title: 'Become a Seller',
      body:
          'Apply to sell on AgroBenta. An administrator reviews every '
          'application, and your account becomes a seller only after approval.',
      action: FilledButton(
        onPressed: onStart,
        child: const Text('Start seller verification'),
      ),
    );
  }
}

/// Filed and waiting for an administrator.
///
/// Deliberately offers no form and no "edit" action. A second application is
/// refused by the server with a `409`, so showing a form here would invite the
/// user into a dead end and then tell them off for entering it.
class SellerVerificationAwaitingReviewView extends StatelessWidget {
  const SellerVerificationAwaitingReviewView({
    required this.verification,
    super.key,
  });

  /// The open record.
  ///
  /// Non-null: the controller only publishes [SellerVerificationUiStatus
  /// .awaitingReview] together with a record the server returned, and the screen
  /// falls back to the "never applied" view when there is no record at all.
  final SellerVerification verification;

  @override
  Widget build(BuildContext context) {
    return SellerVerificationStatusCard(
      icon: Icons.hourglass_empty,
      accent: AppColors.warning,
      title: 'Under review',
      body:
          'Your application is with an administrator. You will be able to sell '
          'once it is approved. You cannot send another application while this '
          'one is being reviewed.',
      children: <Widget>[
        DetailRow(label: 'Business', value: verification.businessName),
        if (verification.submittedAt != null)
          DetailRow(
            label: 'Submitted',
            value: AppFormatters.formatDateTime(verification.submittedAt),
          ),
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
    return SellerVerificationStatusCard(
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
