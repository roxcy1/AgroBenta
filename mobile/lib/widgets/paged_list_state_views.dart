import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';

/// The footer under the last page of a paginated list.
///
/// Shows a spinner while the next page loads, a retry when that page failed,
/// and end-of-list space when the server has no next page.
class PagedListLoadMoreFooter extends StatelessWidget {
  const PagedListLoadMoreFooter({
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
            OutlinedButton(
              onPressed: onLoadMore,
              child: const Text('Try again'),
            ),
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

/// A pull-to-refresh that failed, shown above results still on screen.
class PagedListRefreshNotice extends StatelessWidget {
  const PagedListRefreshNotice({
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
          const Icon(
            Icons.sync_problem_outlined,
            size: 18,
            color: AppColors.error,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.text),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
