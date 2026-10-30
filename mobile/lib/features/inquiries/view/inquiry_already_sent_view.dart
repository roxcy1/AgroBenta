import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/listing.dart';
import '../widgets/inquiry_listing_card.dart';

/// The "Inquiry Already Sent" state — shown when the pre-check finds that this
/// buyer has already asked about this listing.
///
/// The rule is one inquiry per buyer per listing, whatever its status, so the
/// form is not rendered at all: offering it would only produce a `409`. The
/// buyer is pointed at Messages, where any conversation with the seller lives,
/// or back to Browse.
///
/// This view claims nothing the pre-check did not prove. It shows the real
/// [Listing] the screen was opened with and the exact approved copy; it does
/// not invent a status, a timestamp or a conversation that does not exist.
class InquiryAlreadySentView extends StatelessWidget {
  const InquiryAlreadySentView({
    required this.listing,
    required this.onGoToMessages,
    required this.onBackToBrowse,
    super.key,
  });

  /// The listing the buyer already asked about.
  final Listing listing;

  /// Opens the existing Messages inbox.
  final VoidCallback onGoToMessages;

  /// Returns to the buyer shell's Browse destination.
  final VoidCallback onBackToBrowse;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: AppSpacing.xs),
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppColors.primarySurface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_read_outlined,
                  size: 32,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Inquiry Already Sent',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                "You've already sent an inquiry about this livestock. You can "
                'continue the conversation in Messages.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              InquiryListingCard(listing: listing),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onGoToMessages,
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: const Text('Go to Messages'),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: onBackToBrowse,
                icon: const Icon(Icons.chevron_left),
                label: const Text('Back to Browse'),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}
