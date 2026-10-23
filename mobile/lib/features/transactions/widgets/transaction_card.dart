import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/listing.dart';
import '../../../models/transaction.dart';
import 'transaction_status_badge.dart';

/// One purchase in the My Purchases list.
///
/// A card the buyer can judge at a glance: TRX-ID and date, what it is, the
/// server's agreed amount with a label that cannot be mistaken for the
/// listing's asking price, and an unmistakable status badge. Deliberately
/// **not** every column — quantity and the counterparty belong on the detail
/// screen.
///
/// The amount is `total_amount` from the API (the server's `asking_price ×
/// quantity`). It is never computed here: any client-side arithmetic that
/// differed from the server would be a trust bug. It is shown exactly, with
/// cents, because this is a purchase record rather than a browsable listing.
///
/// There is no location row: `MobileTransactionResource` does not expose one.
///
/// Tappable as a whole. The [onTap] target is the full card.
class TransactionCard extends StatelessWidget {
  const TransactionCard({
    required this.transaction,
    required this.onTap,
    super.key,
  });

  final Transaction transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? photoUrl = transaction.listing.loadablePhotoUrl;
    final String date = AppFormatters.formatDate(transaction.createdAt);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Thumbnail(photoUrl: photoUrl),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Reference and date in one compact secondary row: they
                    // identify the record without competing with the title.
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            transaction.displayId,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (date.isNotEmpty) ...<Widget>[
                          const SizedBox(width: AppSpacing.xs),
                          Text(date, style: theme.textTheme.labelSmall),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      transaction.listing.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    // The label is not decoration: it distinguishes the
                    // persisted transaction amount from a listing's asking
                    // price, which this screen never shows.
                    Text('Agreed price', style: theme.textTheme.labelSmall),
                    Text(
                      AppFormatters.formatMoney(transaction.totalAmount) ??
                          transaction.totalAmount,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    TransactionStatusBadge(status: transaction.status),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              // The card opens the existing detail route, so it says so.
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.xxs),
                child: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small square thumbnail, or an honest placeholder.
///
/// Draws a network image only when the stored value is already an absolute
/// `http`/`https` URL. Anything else gets a neutral placeholder — inventing
/// a base URL would fabricate a storage mechanism that does not exist.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    const double size = 72;

    final Widget placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: const Icon(
        Icons.image_not_supported_outlined,
        size: 22,
        color: AppColors.textSecondary,
      ),
    );

    final String? url = photoUrl;
    if (url == null || !Listing.isDirectlyLoadablePhotoUrl(url)) {
      return placeholder;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Image.network(
        url.trim(),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (BuildContext context, Object error, StackTrace? _) =>
            placeholder,
        excludeFromSemantics: true,
      ),
    );
  }
}
