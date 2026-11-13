import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/listing.dart';
import '../../../models/transaction.dart';
import '../../../widgets/livestock_type_icon.dart';
import 'transaction_status_badge.dart';

/// One transaction in My Purchases or My Sales.
///
/// A card either party can judge at a glance: TRX-ID and date, what it is, the
/// server's agreed amount with a label that cannot be mistaken for the
/// listing's asking price, and an unmistakable status badge. Deliberately
/// **not** every column — quantity and the counterparty belong on the detail
/// screen.
///
/// The amount is `total_amount` from the API (the server's `asking_price ×
/// quantity`). It is never computed here: any client-side arithmetic that
/// differed from the server would be a trust bug. It is shown exactly, with
/// cents, because this is a transaction record rather than a browsable listing.
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  _Thumbnail(
                    photoUrl: photoUrl,
                    type: transaction.listing.livestockType,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          transaction.listing.title,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${transaction.role == TransactionRole.buyer ? 'Seller' : 'Buyer'}: '
                          '${transaction.counterparty.name}',
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // The reference identifies the record in support
                        // conversations without competing with the title.
                        Text(
                          transaction.displayId,
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  TransactionStatusBadge(status: transaction.status),
                  // The card opens the existing detail route, so it says so.
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Divider(height: 1),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Expanded(
                    child: Text(date, style: theme.textTheme.labelMedium),
                  ),
                  // The label is not decoration: it distinguishes the
                  // persisted transaction amount from a listing's asking
                  // price, which this screen never shows.
                  Text('Agreed price', style: theme.textTheme.labelSmall),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      AppFormatters.formatMoney(transaction.totalAmount) ??
                          transaction.totalAmount,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.photoUrl, required this.type});

  final String? photoUrl;

  /// The livestock type, drawn as a silhouette when there is no photo.
  final String type;

  @override
  Widget build(BuildContext context) {
    const double size = 56;

    final Widget placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(AppRadius.sm - 2),
      ),
      child: Center(
        child: LivestockTypeIcon(
          type: type,
          size: 26,
          color: AppColors.primary.withValues(alpha: 0.6),
        ),
      ),
    );

    final String? url = photoUrl;
    if (url == null || !Listing.isDirectlyLoadablePhotoUrl(url)) {
      return placeholder;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm - 2),
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
