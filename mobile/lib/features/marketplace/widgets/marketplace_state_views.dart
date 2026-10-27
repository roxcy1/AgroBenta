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
  const MarketplaceEmptyState({
    required this.isFiltered,
    this.onClear,
    super.key,
  });

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
    this.title = 'Could not load listings',
    super.key,
  });

  /// A displayable message, already curated by `ApiClient`.
  final String message;

  final VoidCallback onRetry;

  /// The heading above [message]. Defaults to the marketplace's own copy; a
  /// non-marketplace caller (for example the transaction detail screen) passes
  /// its own noun so the error never names the wrong thing.
  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 40, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
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
