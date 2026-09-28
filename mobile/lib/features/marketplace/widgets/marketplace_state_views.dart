import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// The list loaded successfully but contains no listings.
///
/// [isFiltered] changes the wording and the action, because the two situations
/// call for different things from the buyer. "There are no active listings yet"
/// is a fact about the marketplace and nothing the buyer can do; "No listings
/// match your search" is a fact about their query, and offering to clear it is
/// the useful response. Saying the wrong one is the standard way an empty state
/// becomes a dead end.
class MarketplaceEmptyState extends StatelessWidget {
  const MarketplaceEmptyState({required this.isFiltered, this.onClear, super.key});

  /// Whether a search or filter is currently narrowing the results.
  final bool isFiltered;

  /// Clears the query. Only supplied when [isFiltered] is true, so the button
  /// cannot appear without a way to make it work.
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
                  : Icons.inventory_2_outlined,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              isFiltered ? 'No listings match' : 'No active listings yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              isFiltered
                  ? 'Try a different search term, or widen your filters.'
                  : 'Newly approved listings from sellers will appear here.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (isFiltered && onClear != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(
                onPressed: onClear,
                child: const Text('Clear search and filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A full-screen failure with a retry.
///
/// Shown only when the **first** page failed. A later page failing must not
/// reach this widget — the listings already on screen are still valid, and
/// replacing them with an error page would throw away results the buyer could
/// still use. That case is handled by the load-more footer instead.
class MarketplaceErrorState extends StatelessWidget {
  const MarketplaceErrorState({
    required this.message,
    required this.onRetry,
    super.key,
  });

  /// A displayable message, already curated by `ApiClient`.
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
              Icons.error_outline,
              size: 40,
              color: AppColors.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Could not load listings',
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

/// The footer under the last page of results: a spinner while loading, an error
/// with a retry if that page failed, and nothing at all when the server has said
/// there is no next page.
///
/// Rendering nothing at the true end of the list is deliberate. A permanent
/// "You've reached the end" footer adds a row of text to every screen for no
/// information — the absence of a spinner is already the signal.
class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({
    required this.isLoading,
    required this.hasMore,
    required this.errorMessage,
    required this.onLoadMore,
    super.key,
  });

  final bool isLoading;
  final bool hasMore;
  final String? errorMessage;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.md,
          AppSpacing.screenGutter,
          AppSpacing.lg,
        ),
        child: Column(
          children: <Widget>[
            Text(
              errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            OutlinedButton(onPressed: onLoadMore, child: const Text('Try again')),
          ],
        ),
      );
    }

    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (!hasMore) {
      return const SizedBox(height: AppSpacing.lg);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.md,
        AppSpacing.screenGutter,
        AppSpacing.lg,
      ),
      child: OutlinedButton(
        onPressed: onLoadMore,
        child: const Text('Load more'),
      ),
    );
  }
}

/// A pull-to-refresh that failed, shown above results that are still on screen.
///
/// Distinct from [MarketplaceErrorState] on purpose: nothing is wrong with the
/// list the user is looking at, the *newer* copy of it could not be fetched, and
/// replacing those cards with an error page would be a worse outcome than
/// briefly stale data. The wording says so rather than leaving the user to guess
/// whether what they see is current.
class RefreshFailedNotice extends StatelessWidget {
  const RefreshFailedNotice({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.sync_problem_outlined, size: 18, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.text,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
