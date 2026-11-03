import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/message.dart';

/// The structured card that replaces the generated inquiry text body.
///
/// The server marks the one message that opened an inquiry; every unit is
/// human-readable (no raw enum values) and the card stays a single element in
/// the otherwise chronological message list. A thread covering several
/// listings shows one card per inquiry, because the backend attaches at most
/// one per inquiry.
class InquiryMessageCard extends StatelessWidget {
  const InquiryMessageCard({
    required this.inquiry,
    required this.isMine,
    super.key,
  });

  final MessageInquiry inquiry;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MessageInquiryListing? listing = inquiry.listing;
    final String? price = listing?.askingPrice == null
        ? null
        : AppFormatters.formatMoney(listing!.askingPrice!) ??
              listing.askingPrice;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.receipt_long_outlined,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    isMine ? 'Your inquiry' : 'Inquiry',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Photo(url: listing?.photoUrl),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          listing?.title ?? 'Listing no longer available',
                          style: theme.textTheme.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (price != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            'Listed at $price',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (inquiry.paymentMethod != null)
                _row(theme, 'Payment', inquiry.paymentMethod!.label),
              if (inquiry.collectionMethod != null)
                _row(theme, 'Collection', inquiry.collectionMethod!.label),
              if (inquiry.preferredSchedule != null)
                _row(
                  theme,
                  'Preferred date',
                  AppFormatters.formatDate(inquiry.preferredSchedule),
                ),
              if (inquiry.message.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    inquiry.message,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.labelMedium)),
        ],
      ),
    );
  }
}

/// The listing photo, falling back to a neutral livestock glyph when the
/// listing has no upload (or was deleted).
class _Photo extends StatelessWidget {
  const _Photo({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final String? source = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(
        width: 64,
        height: 64,
        child: source == null || source.isEmpty
            ? Container(
                color: AppColors.primarySurface,
                child: const Icon(
                  Icons.pets_outlined,
                  color: AppColors.textSecondary,
                ),
              )
            : Image.network(
                source,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: AppColors.primarySurface,
                  child: const Icon(
                    Icons.pets_outlined,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
      ),
    );
  }
}
