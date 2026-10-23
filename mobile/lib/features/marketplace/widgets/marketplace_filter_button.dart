import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../state/marketplace_state.dart';

/// The marketplace's filter control, badged when filters are active.
///
/// A button, not a permanently visible row of every filter. Six filters would
/// not fit on a phone, and a list that only grows as more filters are added
/// would push the results off the screen. The summary in the tooltip covers
/// what is applied for anyone who wants the detail without opening the sheet.
///
/// Shared by the marketplace screen and the Home screen's search bar, so both
/// render the same control and the same active-filter badge from the same
/// [MarketplaceState].
class MarketplaceFilterButton extends StatelessWidget {
  const MarketplaceFilterButton({
    required this.state,
    required this.onPressed,
    super.key,
  });

  final MarketplaceState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String summary = state.filters.summary;
    final bool isActive = state.filters.isActive;

    return Tooltip(
      message: isActive ? 'Filters: $summary' : 'Filters',
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          side: BorderSide(
            color: isActive ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.tune, size: 20),
            if (isActive) ...<Widget>[
              const SizedBox(width: AppSpacing.xxs),
              // A count, not the values: the sheet shows the values, and the
              // count is what fits.
              Text(
                '${state.filters.activeCount}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
