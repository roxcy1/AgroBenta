import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../state/transactions_filter.dart';

/// The All / Ongoing / Completed / Cancelled chip row.
///
/// The design's screenshot also shows a **Pending** chip, but the backend
/// persists a single `pending` state — the same records the Ongoing chip
/// already returns — so a second chip would be a distinction the API cannot
/// make. The row therefore matches the server's three real states plus All.
/// See [TransactionsFilter] and `mobile/DESIGN.md` §26.
class TransactionFilterBar extends StatelessWidget {
  const TransactionFilterBar({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final TransactionsFilter selected;
  final ValueChanged<TransactionsFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    Widget chip(TransactionsFilter filter) {
      final bool isSelected = filter == selected;
      return ChoiceChip(
        label: Text(filter.label),
        selected: isSelected,
        showCheckmark: false,
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.surface,
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.border,
        ),
        labelStyle: theme.textTheme.labelMedium?.copyWith(
          color: isSelected ? Colors.white : AppColors.textSecondary,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
        onSelected: (bool value) {
          if (value) {
            onSelected(filter);
          }
        },
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenGutter),
      child: Row(
        children: <Widget>[
          chip(TransactionsFilter.all),
          for (final TransactionsFilter filter in <TransactionsFilter>[
            TransactionsFilter.ongoing,
            TransactionsFilter.completed,
            TransactionsFilter.cancelled,
          ]) ...<Widget>[const SizedBox(width: AppSpacing.xs), chip(filter)],
        ],
      ),
    );
  }
}
