import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// **Placeholder review data — UI preview only.**
///
/// AgroBenta has no ratings or reviews table, endpoint, submission flow or
/// business rule yet. These two constants exist so the listing card and detail
/// screen can show the approved layout while that feature is undecided. They
/// must be replaced with real API values (and the surrounding widget with a
/// real model) before any release — never presented as genuine feedback.
const String kPlaceholderRating = '4.8';
const int kPlaceholderReviewCount = 24;

/// The completed-sale line plus the placeholder rating, as one compact block.
///
/// Completed sales are real: `MobileListingResource.completed_sales` counts the
/// listing's own completed transactions. The rating line is static placeholder
/// copy, isolated here and labelled as such so it cannot be mistaken for real
/// data by a future reader.
class ListingSocialProof extends StatelessWidget {
  const ListingSocialProof({required this.completedSales, super.key});

  final int completedSales;

  String get _salesLabel => completedSales == 1
      ? '1 completed sale'
      : '$completedSales completed sales';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? style = theme.textTheme.labelSmall?.copyWith(
      color: AppColors.textSecondary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          _salesLabel,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.star_rounded, size: 14, color: AppColors.primary),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                '$kPlaceholderRating · $kPlaceholderReviewCount reviews',
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
