import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/inquiry.dart';
import '../../../models/received_inquiry.dart';

/// One inquiry in the seller's received-inquiry list.
///
/// The seller's inbox has no detail endpoint in this phase, so the card shows
/// the whole inquiry rather than a preview that would hide text behind a route
/// that does not exist. The buyer is identity and name only, matching
/// `SellerInquiryResource`; no email is modelled or rendered.
///
/// There is deliberately no status badge: the administrator-facing inquiry
/// status is not part of the mobile API. A seller may answer with the
/// structured purchase offer this card's optional action opens — not by
/// re-statusing the inquiry, which remains an administrator bookmark.
class ReceivedInquiryCard extends StatelessWidget {
  const ReceivedInquiryCard({
    required this.inquiry,
    this.onMakeOffer,
    super.key,
  });

  final ReceivedInquiry inquiry;

  /// Opens the make-offer form for this inquiry. `null` when the buyer or
  /// listing projection is missing, because an offer without them cannot be
  /// created truthfully.
  final VoidCallback? onMakeOffer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String buyerName = inquiry.buyer?.name ?? 'Unknown buyer';
    final String date = AppFormatters.formatDateTime(inquiry.createdAt);
    final String? subject = inquiry.subject?.trim();
    final String? preferences = _preferences();
    final String? schedule = inquiry.preferredSchedule == null
        ? null
        : 'Preferred date: '
              '${AppFormatters.formatDate(inquiry.preferredSchedule)}';
    final String? deliveryFee = inquiry.deliveryFee == null
        ? null
        : 'Proposed delivery fee: '
              '${AppFormatters.formatMoney(inquiry.deliveryFee) ?? inquiry.deliveryFee}';
    final String? collectionPlan =
        inquiry.collectionDateOption == null ||
            inquiry.collectionDateOption ==
                InquiryCollectionDateOption.specificDate
        ? null
        : 'Collection plan: ${inquiry.collectionDateOption!.label}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    buyerName,
                    style: theme.textTheme.titleSmall,
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.pets_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    _listingLabel(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            if (subject != null && subject.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(subject, style: theme.textTheme.titleSmall),
            ],
            const SizedBox(height: AppSpacing.xs),
            Text(inquiry.message, style: theme.textTheme.bodySmall),
            if (inquiry.purchaseInterest == true) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  'Wants to buy',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            if (preferences != null ||
                schedule != null ||
                collectionPlan != null ||
                deliveryFee != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              if (preferences != null)
                Text(preferences, style: theme.textTheme.bodySmall),
              if (schedule != null) ...<Widget>[
                if (preferences != null) const SizedBox(height: AppSpacing.xxs),
                Text(schedule, style: theme.textTheme.bodySmall),
              ],
              if (collectionPlan != null) ...<Widget>[
                if (preferences != null || schedule != null)
                  const SizedBox(height: AppSpacing.xxs),
                Text(collectionPlan, style: theme.textTheme.bodySmall),
              ],
              if (deliveryFee != null) ...<Widget>[
                if (preferences != null ||
                    schedule != null ||
                    collectionPlan != null)
                  const SizedBox(height: AppSpacing.xxs),
                Text(deliveryFee, style: theme.textTheme.bodySmall),
              ],
            ],
            if (onMakeOffer != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onMakeOffer,
                  icon: const Icon(Icons.local_offer_outlined, size: 18),
                  label: const Text('Make an offer'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _listingLabel() {
    final InquiryListing? listing = inquiry.listing;
    if (listing == null) {
      return 'Listing no longer available';
    }
    final String breed = listing.breed.trim();
    return breed.isEmpty
        ? listing.livestockType
        : '${listing.livestockType} - $breed';
  }

  String? _preferences() {
    final List<String> values = <String>[
      if (inquiry.paymentMethod != null) inquiry.paymentMethod!.label,
      if (inquiry.collectionMethod != null) inquiry.collectionMethod!.label,
      if (inquiry.transactionMethod != null) inquiry.transactionMethod!.label,
      if (inquiry.deliveryMethod != null) inquiry.deliveryMethod!.label,
      if (inquiry.contactMethod != null) inquiry.contactMethod!.label,
    ];
    return values.isEmpty ? null : values.join(' / ');
  }
}
