import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/livestock_type.dart';
import '../../../widgets/livestock_type_icon.dart';
import '../../livestock_types/state/livestock_types_scope.dart';
import '../../livestock_types/state/livestock_types_state.dart';

/// One buyer-facing browse category: a stable id, a label, an icon, and the
/// `livestock_type` filter value a tap applies.
///
/// The labels come from the backend-owned catalog, so an approved category is
/// available here without a second client-side list. The filter value is the
/// catalog value, sent as the marketplace's existing exact-match
/// `livestock_type` filter — the category tiles do not invent an endpoint or a
/// query parameter, they drive the same filter the marketplace sheet does.
///
/// Historical listings may still hold seller-typed values outside the catalog;
/// those remain readable, but a category tile filters by the canonical value.
@immutable
class HomeCategory {
  const HomeCategory({
    required this.id,
    required this.label,
    required this.livestockType,
  });

  /// Stable identifier, independent of the label text.
  final String id;

  /// What the buyer sees on the tile.
  final String label;

  /// The exact `livestock_type` string sent to the marketplace filter.
  final String livestockType;

  factory HomeCategory.fromCatalog(LivestockType type) => HomeCategory(
    id: type.value,
    label: type.label,
    livestockType: type.value,
  );
}

/// "Browse by Category": a heading and a responsive grid of pale-green tiles.
///
/// Each tile is a single tap target well past the 48dp minimum, and the whole
/// tile — not just the icon — is the button. Tapping one is handed to
/// [onSelect], which applies the category's `livestock_type` through the
/// existing marketplace filter and navigates to the marketplace.
class HomeCategories extends StatelessWidget {
  const HomeCategories({required this.onSelect, this.onSeeAll, super.key});

  /// Applies [HomeCategory.livestockType] via the marketplace filter.
  final ValueChanged<HomeCategory> onSelect;

  /// Opens the full marketplace, when a destination is supplied.
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final controller = LivestockTypesScope.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Browse by Category',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (onSeeAll != null)
                TextButton(onPressed: onSeeAll, child: const Text('See All')),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ListenableBuilder(
            listenable: controller,
            builder: (BuildContext context, Widget? child) {
              final LivestockTypesState catalog = controller.state;
              if (!catalog.isReady) {
                if (catalog.hasFailed) {
                  return Row(
                    children: <Widget>[
                      const Expanded(child: Text('Could not load categories.')),
                      TextButton(
                        onPressed: controller.retry,
                        child: const Text('Retry'),
                      ),
                    ],
                  );
                }
                return const Center(child: CircularProgressIndicator());
              }
              final List<HomeCategory> categories = catalog.types
                  .map(HomeCategory.fromCatalog)
                  .toList(growable: false);
              return LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  const double spacing = AppSpacing.sm;
                  // Four to a row on a phone, matching the approved design;
                  // more on wider screens.
                  final int columns = (constraints.maxWidth / 80).floor().clamp(
                    4,
                    6,
                  );
                  final double tileWidth =
                      (constraints.maxWidth - (columns - 1) * spacing) /
                      columns;

                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: <Widget>[
                      for (final HomeCategory category in categories)
                        _CategoryTile(
                          category: category,
                          width: tileWidth,
                          onTap: () => onSelect(category),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One category tile: a pale-green rounded square with the icon above the
/// label. The ink splash covers the whole tile, so the touch target is the
/// tile itself.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.width,
    required this.onTap,
  });

  final HomeCategory category;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // A square icon tile with the label underneath it. The whole column is
    // one tap target.
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Column(
            children: <Widget>[
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                alignment: Alignment.center,
                child: LivestockTypeIcon(
                  type: category.livestockType,
                  size: 34,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                category.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.text,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
