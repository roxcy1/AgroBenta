import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/listing.dart';
import '../../../widgets/notice_banner.dart';

/// The display word for a listing status.
///
/// The word carries the meaning and the chip is only a frame, so a status is
/// still readable on a greyscale screen or to someone who does not distinguish
/// the colours. "Pending" on its own is ambiguous in a list that also contains
/// drafts and sold listings, so the seller's own view says "Pending review" — the
/// longer form is what the state actually is, and the marketplace never shows
/// this status at all so there is nothing to keep consistent with.
///
/// An exhaustive switch rather than a lookup map: adding a sixth status to the
/// server's enum should be a compile error here, not a silent `Unknown`.
String listingStatusLabel(ListingStatus status) => switch (status) {
  ListingStatus.draft => 'Draft',
  ListingStatus.pending => 'Pending review',
  ListingStatus.active => 'Active',
  ListingStatus.sold => 'Sold',
  ListingStatus.inactive => 'Inactive',
};

/// What a status means for this seller, in one sentence.
///
/// Explaining the state is the point of a seller-facing list: a buyer only ever
/// sees `active`, so `pending` in particular arrives with no context at all, and
/// a seller who has just submitted needs to be told the next step is not theirs
/// to take.
String listingStatusExplanation(ListingStatus status) => switch (status) {
  ListingStatus.draft =>
    'Only you can see this listing. Edit it, submit it for review, or delete '
        'it.',
  ListingStatus.pending =>
    'An administrator is reviewing this listing. It is not visible in the '
        'marketplace yet, and it cannot be changed while it is being reviewed.',
  ListingStatus.active =>
    'This listing is live in the marketplace. You can still edit its details.',
  ListingStatus.sold =>
    'This listing was sold. It stays here as a record and can no longer be '
        'changed.',
  ListingStatus.inactive =>
    'This listing is no longer in the marketplace. It is kept here as a '
        'record and can be deleted.',
};

/// The accent that supports a status without carrying it.
Color listingStatusAccent(ListingStatus status) => switch (status) {
  ListingStatus.draft => AppColors.textSecondary,
  ListingStatus.pending => AppColors.warning,
  ListingStatus.active => AppColors.success,
  ListingStatus.sold => AppColors.textSecondary,
  ListingStatus.inactive => AppColors.textSecondary,
};

/// A listing's status, as a restrained chip.
///
/// A tinted background, matching text and a 6px radius, per the status-indicator
/// rule in `mobile/DESIGN.md`. Only statuses are chips: prices, names and dates
/// stay plain text, because a pill for every value is one of the documented
/// anti-patterns.
class ListingStatusChip extends StatelessWidget {
  const ListingStatusChip({
    required this.status,
    this.dense = false,
    super.key,
  });

  final ListingStatus status;

  /// Drops the padding, for a row that is already tight.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final Color accent = listingStatusAccent(status);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.xs : AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        listingStatusLabel(status),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: accent),
      ),
    );
  }
}

/// A `409`: the listing is not in a state for that action.
///
/// Amber rather than red, and worded as information. The seller's request was
/// well-formed; the listing has simply moved on — it was already submitted, or an
/// administrator has since decided something. Showing this in the same red banner
/// as a network failure would tell them they did something wrong at the exact
/// moment the answer is "there is nothing to fix here".
class ListingConflictNotice extends StatelessWidget {
  const ListingConflictNotice({required this.message, super.key});

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

/// A management action failed, for a reason the user may be able to fix.
class ListingActionErrorBanner extends StatelessWidget {
  const ListingActionErrorBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return NoticeBanner(
      accent: AppColors.error,
      icon: Icons.error_outline,
      message: message,
      backgroundColor: AppColors.error.withValues(alpha: 0.06),
    );
  }
}

/// The seller has no listings at all.
class SellerListingsEmptyState extends StatelessWidget {
  const SellerListingsEmptyState({
    required this.isFiltered,
    required this.onCreate,
    this.onClear,
    super.key,
  });

  /// Whether a search or status filter is narrowing the results.
  ///
  /// Changes both the wording and the action, because the two situations call for
  /// different things. "You have not created a listing yet" is a fact about the
  /// account and the useful response is to create one; "No listings match" is a
  /// fact about the query, and the useful response is to widen it. Offering to
  /// create a listing in the second case would be answering a question nobody
  /// asked.
  final bool isFiltered;

  final VoidCallback onCreate;

  /// Clears the query. Only supplied when [isFiltered] is true.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              isFiltered
                  ? Icons.search_off_outlined
                  : Icons.add_business_outlined,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              isFiltered ? 'No listings match' : 'No listings yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              isFiltered
                  ? 'Try a different search, or clear the status filter.'
                  : 'Create your first listing as a draft, then submit it for '
                        'review when it is ready.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (isFiltered && onClear != null)
              OutlinedButton(
                onPressed: onClear,
                child: const Text('Clear search and filter'),
              )
            else
              FilledButton(
                onPressed: onCreate,
                child: const Text('Create a listing'),
              ),
          ],
        ),
      ),
    );
  }
}

/// The list could not be loaded at all.
class SellerListingsErrorState extends StatelessWidget {
  const SellerListingsErrorState({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

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
              'Could not load your listings',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
