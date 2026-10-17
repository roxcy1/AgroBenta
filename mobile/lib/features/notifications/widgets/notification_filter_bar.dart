import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';

/// The category filter chips above the notifications list.
///
/// The first chip is always "All" and its value is `null` — the absence of a
/// `type` query parameter is what "show everything" means to the server. The
/// rest come from [NotificationEndpoints.filterTypes] indirectly (via the
/// screen), because the chip labels and the query values are the same four
/// strings the backend accepts.
class NotificationFilterBar extends StatelessWidget {
  const NotificationFilterBar({
    required this.filters,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// The filter values (in order) *excluding* "All". `null` is the "All" chip.
  final List<String> filters;

  /// The active filter value, or `null` for "All".
  final String? selected;

  /// Called with `null` for "All" and a filter value otherwise.
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final List<String?> chips = <String?>[null, ...filters];

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
        ),
        itemCount: chips.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: AppSpacing.xs),
        itemBuilder: (BuildContext context, int index) {
          final String? value = chips[index];
          final bool isSelected = value == selected;
          final String label = value == null
              ? 'All'
              : '${value[0].toUpperCase()}${value.substring(1)}';

          return Center(
            child: ChoiceChip(
              label: Text(label),
              selected: isSelected,
              showCheckmark: false,
              onSelected: (bool v) {
                if (v) {
                  onSelected(value);
                }
              },
            ),
          );
        },
      ),
    );
  }
}