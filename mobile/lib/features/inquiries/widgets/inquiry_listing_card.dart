import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/listing.dart';
import '../../marketplace/widgets/listing_photo.dart';

/// The selected listing at the top of the inquiry flow: photo, title, price,
/// seller name, location, and the attributes the API actually supplied.
///
/// Shared by the Inquire form and the Inquiry Sent confirmation so both show
/// the identical summary of the same [Listing] instance — no field is
/// invented, and the price is rendered as reference-only (design spec §3.2).
/// The photo is the shared [ListingPhoto], which shows an honest placeholder
/// whenever the API has not supplied a fetchable URL.
class InquiryListingCard extends StatelessWidget {
  const InquiryListingCard({required this.listing, super.key});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? age = listing.ageLabel;
    final String? weight = listing.weightLabel;
    final List<String> attributes = <String>[
      ?age,
      ?weight,
      ?listing.genderLabel,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ListingPhoto(listing: listing, width: 72, height: 72),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    listing.livestockType.toUpperCase(),
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(listing.title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    AppFormatters.formatMoney(listing.askingPrice) ??
                        listing.askingPrice,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  if (listing.seller.name.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.person_outline,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Expanded(
                          child: Text(
                            listing.seller.name,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (attributes.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      attributes.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (listing.location.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Expanded(
                          child: Text(
                            listing.location,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
