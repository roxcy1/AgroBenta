import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/transaction_receipt.dart';

/// The receipt document itself.
///
/// Deliberately a self-contained visual block: it is what Phase 4 captures as a
/// PNG, so it must not depend on screen chrome, scrolling position or remote
/// images. Every value comes from the server's receipt snapshot.
class TransactionReceiptCard extends StatelessWidget {
  const TransactionReceiptCard({required this.receipt, super.key});

  final TransactionReceipt receipt;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? total = AppFormatters.formatMoney(receipt.totalAmount);
    final String quantity =
        '${receipt.quantity} ${receipt.quantity == 1 ? 'head' : 'heads'}';
    final String completed = receipt.completedAt == null
        ? 'Not recorded'
        : AppFormatters.formatDateTime(receipt.completedAt);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Image.asset(
                'assets/images/AgroBentaLogo.png',
                height: 52,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'AgroBenta',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Digital Livestock Purchase Receipt',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Record of a completed sale',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            _ValueBlock(label: 'Receipt number', value: receipt.reference),
            const SizedBox(height: AppSpacing.sm),
            _ValueBlock(label: 'Completed', value: completed),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            _ValueBlock(label: 'Buyer', value: receipt.buyerName),
            const SizedBox(height: AppSpacing.sm),
            _ValueBlock(label: 'Seller', value: receipt.sellerName),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            Text('Livestock', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            _ValueBlock(label: 'Type', value: receipt.livestockType),
            if (receipt.breed.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              _ValueBlock(label: 'Breed', value: receipt.breed),
            ],
            const SizedBox(height: AppSpacing.sm),
            _ValueBlock(label: 'Quantity', value: quantity),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            Text('Agreed price', style: theme.textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              total ?? receipt.totalAmount,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _ValueBlock(
              label: 'Fulfillment method',
              value: receipt.collectionMethodLabel,
            ),
            const SizedBox(height: AppSpacing.sm),
            _ValueBlock(
              label: 'Preferred payment method',
              value: receipt.paymentMethodLabel,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Not verified by AgroBenta.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            Text(
              'This receipt records the completed sale in AgroBenta. It is not '
              'proof of payment. Payment and delivery were arranged directly '
              'between the buyer and seller.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A stacked label/value block, matching the app's existing detail rows.
class _ValueBlock extends StatelessWidget {
  const _ValueBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(value, style: theme.textTheme.bodyLarge),
      ],
    );
  }
}
