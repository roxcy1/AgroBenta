import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/transaction.dart';
import '../state/transactions_filter.dart';

/// The empty state for one purchases or sales filter.
///
/// Fixed copy per filter and viewer side. Completed records reach this filter
/// after the buyer confirms receipt on a delivered/picked-up transaction.
class TransactionsEmptyState extends StatelessWidget {
  const TransactionsEmptyState({
    required this.filter,
    required this.role,
    super.key,
  });

  final TransactionsFilter filter;
  final TransactionRole role;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isSeller = role == TransactionRole.seller;
    final (String title, String body) = switch (filter) {
      TransactionsFilter.all =>
        isSeller
            ? (
                'No sales yet',
                'Transactions buyers start from your listings will appear here.',
              )
            : (
                'No purchases yet',
                'Transactions you start from a listing will appear here.',
              ),
      TransactionsFilter.ongoing =>
        isSeller
            ? (
                'No ongoing sales yet',
                'Sales that are still pending will appear here.',
              )
            : (
                'No ongoing purchases yet',
                'Purchases that are still pending will appear here.',
              ),
      TransactionsFilter.completed =>
        isSeller
            ? (
                'No completed sales yet',
                'Sales completed after buyer receipt confirmation will appear here.',
              )
            : (
                'No completed purchases yet',
                'Purchases completed after you confirm receipt will appear here.',
              ),
      TransactionsFilter.cancelled =>
        isSeller
            ? (
                'No cancelled sales',
                'Sales cancelled by either party will appear here.',
              )
            : (
                'No cancelled purchases',
                'Purchases cancelled by either party will appear here.',
              ),
    };

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.receipt_long_outlined,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              body,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// A full-screen failure with a retry, for the first page only.
class TransactionsErrorState extends StatelessWidget {
  const TransactionsErrorState({
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
              Icons.error_outline,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Could not load transactions',
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
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
