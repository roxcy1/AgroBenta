import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_input_border.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/livestock_type.dart';
import '../state/seller_listing_filters.dart';
import '../state/seller_profile_state.dart';

/// Search, category chips and ordering for the Listings tab.
///
/// Every control changes the server query, not the loaded page: the controller
/// re-requests page 1 with the same filters and pagination continues under
/// them. The category chips come from the backend-owned livestock catalog, so
/// the app does not keep a second copy of the approved list.
class SellerProfileFilters extends StatelessWidget {
  const SellerProfileFilters({
    required this.searchController,
    required this.state,
    required this.types,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onClearSearch,
    required this.onSelectCategory,
    required this.onSelectSort,
    required this.onClearFilters,
    super.key,
  });

  final TextEditingController searchController;
  final SellerProfileState state;
  final List<LivestockType> types;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchSubmitted;
  final VoidCallback onClearSearch;
  final ValueChanged<String?> onSelectCategory;
  final ValueChanged<SellerListingSort> onSelectSort;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            onChanged: onSearchChanged,
            onSubmitted: (String _) => onSearchSubmitted(),
            decoration: InputDecoration(
              hintText: 'Search this seller’s livestock',
              prefixIcon: const Icon(Icons.search, size: 20),
              contentPadding: AppInputs.plainPadding,
              filled: true,
              fillColor: AppColors.surface,
              border: _roundedBorder(AppColors.border),
              enabledBorder: _roundedBorder(AppColors.border),
              focusedBorder: _roundedBorder(AppColors.primary),
              suffixIcon: state.searchText.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Clear search',
                      onPressed: onClearSearch,
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: types.length + 1,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(width: AppSpacing.xs),
              itemBuilder: (BuildContext context, int index) {
                final LivestockType? type = index == 0
                    ? null
                    : types[index - 1];
                final String value = type?.value ?? '';
                final bool selected =
                    state.livestockType.toLowerCase() == value.toLowerCase();

                return ChoiceChip(
                  key: ValueKey<String>(
                    'seller-category-${value.isEmpty ? 'all' : value}',
                  ),
                  label: Text(type?.label ?? 'All'),
                  selected: selected,
                  showCheckmark: false,
                  selectedColor: AppColors.primarySurface,
                  backgroundColor: AppColors.surface,
                  side: BorderSide(
                    color: selected ? AppColors.primary : AppColors.border,
                  ),
                  labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  onSelected: (_) =>
                      onSelectCategory(value.isEmpty ? null : value),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Expanded(
                child: _SortControl(
                  selected: state.sort,
                  onSelected: onSelectSort,
                ),
              ),
              if (state.hasActiveListingFilters) ...<Widget>[
                const SizedBox(width: AppSpacing.xs),
                TextButton.icon(
                  onPressed: onClearFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static OutlineInputBorder _roundedBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.xl),
    borderSide: BorderSide(color: color),
  );
}

/// A compact menu that shows the current ordering and opens the four options.
class _SortControl extends StatelessWidget {
  const _SortControl({required this.selected, required this.onSelected});

  final SellerListingSort selected;
  final ValueChanged<SellerListingSort> onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return PopupMenuButton<SellerListingSort>(
      initialValue: selected,
      tooltip: 'Sort listings',
      onSelected: onSelected,
      itemBuilder: (BuildContext context) =>
          <PopupMenuEntry<SellerListingSort>>[
            for (final SellerListingSort sort in SellerListingSort.values)
              CheckedPopupMenuItem<SellerListingSort>(
                value: sort,
                checked: sort == selected,
                child: Text(sort.label),
              ),
          ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Row(
          children: <Widget>[
            const ExcludeSemantics(
              child: Icon(
                Icons.swap_vert,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Expanded(
              child: Text(
                selected.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.text,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const ExcludeSemantics(
              child: Icon(
                Icons.arrow_drop_down,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
