import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/listing.dart';
import '../../../models/transaction.dart';
import '../../../repositories/transaction_repository.dart';
import 'buy_sheet_form.dart';

/// The Buy / Inquire sheet: quantity selector feeding the create call.
///
/// Hidden entirely on the seller's own listing — a seller has no create
/// endpoint and cannot transact with themselves (§6.2, backend 409). The
/// caller decides visibility from `listing.seller.id != currentUser.id`;
/// this sheet only handles the purchase itself.
///
/// The quantity feeds `POST /transactions { listing_id, quantity }` and
/// nothing else. No client-side amount is shown or computed: `total_amount`
/// is `asking_price × quantity` server-derived, and any local arithmetic
/// that differed from the server would be a trust bug.
class BuySheet extends StatelessWidget {
  const BuySheet({required this.listing, required this.repository, super.key});

  final Listing listing;
  final TransactionRepository repository;

  /// Shows the sheet and returns the created transaction, or `null` when
  /// dismissed or failed.
  static Future<Transaction?> show(
    BuildContext context, {
    required Listing listing,
    required TransactionRepository repository,
  }) {
    return showModalBottomSheet<Transaction>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) =>
          BuySheet(listing: listing, repository: repository),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.screenGutter,
          right: AppSpacing.screenGutter,
          top: AppSpacing.lg,
          bottom: AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Buy / Inquire', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(listing.title, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${AppFormatters.formatMoney(listing.askingPrice) ?? listing.askingPrice} per head · '
              '${listing.quantity} ${listing.quantity == 1 ? 'head' : 'heads'} available',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            BuySheetForm(listing: listing, repository: repository),
          ],
        ),
      ),
    );
  }
}
