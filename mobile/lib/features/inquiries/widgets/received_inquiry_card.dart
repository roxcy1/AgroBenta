import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/inquiry.dart';
import '../../../models/received_inquiry.dart';
import '../../../widgets/livestock_type_icon.dart';

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
    this.onOpenConversation,
    super.key,
  });

  final ReceivedInquiry inquiry;

  /// Opens the make-offer form; `null` hides the action.
  final VoidCallback? onMakeOffer;

  /// Opens the existing buyer–seller chat. `null` hides the action (no buyer
  /// projection, so the counterpart is unknown).
  final VoidCallback? onOpenConversation;

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
            const SizedBox(height: AppSpacing.sm),
            _ListingStrip(listing: inquiry.listing, label: _listingLabel()),
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
            if (onMakeOffer != null || onOpenConversation != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xxs,
                children: <Widget>[
                  if (onOpenConversation != null)
                    OutlinedButton.icon(
                      onPressed: onOpenConversation,
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: const Text('Open conversation'),
                    ),
                  if (onMakeOffer != null)
                    FilledButton.icon(
                      onPressed: onMakeOffer,
                      icon: const Icon(Icons.local_offer_outlined, size: 18),
                      label: const Text('Make an offer'),
                    ),
                ],
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

/// The livestock the buyer asked about: its picture, name and asking price.
///
/// Showing the animal itself lets a seller with several listings tell
/// inquiries apart at a glance. A listing without photos shows its type's
/// silhouette instead; a deleted listing shows only [label].
class _ListingStrip extends StatelessWidget {
  const _ListingStrip({required this.listing, required this.label});

  final InquiryListing? listing;
  final String label;

  static const double _thumb = 52;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final InquiryListing? listing = this.listing;
    final String? price = listing == null
        ? null
        : AppFormatters.formatMoney(listing.askingPrice);
    final String? photo = listing?.photoUrl;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm - 2),
            child: SizedBox.square(
              dimension: _thumb,
              child: photo != null && photo.isNotEmpty
                  ? Image.network(
                      photo,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _placeholder(),
                    )
                  : _placeholder(),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (price != null)
                  Text(
                    price,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => ColoredBox(
    color: AppColors.primarySurface,
    child: Center(
      child: LivestockTypeIcon(
        type: listing?.livestockType ?? '',
        size: 28,
        color: AppColors.primary,
      ),
    ),
  );
}
