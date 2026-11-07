import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/livestock_type.dart';
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
    required this.icon,
  });

  /// Stable identifier, independent of the label text.
  final String id;

  /// What the buyer sees on the tile.
  final String label;

  /// The exact `livestock_type` string sent to the marketplace filter.
  final String livestockType;

  /// The tile's glyph. Font Awesome Free, no emoji.
  ///
  /// Typed [FaIconData] rather than `IconData`: `font_awesome_flutter` 11.x
  /// made `IconData` a `final` class, so `FaIconData` is no longer a subtype
  /// of it and cannot be assigned to an `IconData` field.
  final FaIconData icon;

  factory HomeCategory.fromCatalog(LivestockType type) => HomeCategory(
    id: type.value,
    label: type.label,
    livestockType: type.value,
    icon: switch (type.value) {
      'cattle' => FontAwesomeIcons.cow,
      'carabao' => FontAwesomeIcons.hippo,
      'goat' => FontAwesomeIcons.paw,
      'swine' => FontAwesomeIcons.bacon,
      'chicken' => FontAwesomeIcons.egg,
      _ => FontAwesomeIcons.paw,
    },
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
                  final int columns = (constraints.maxWidth / 116)
                      .floor()
                      .clamp(3, 5);
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

    return Material(
      color: AppColors.primarySurface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: 84,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              FaIcon(category.icon, size: 22, color: AppColors.primary),
              const SizedBox(height: AppSpacing.xs),
              Text(
                category.label,
                style: theme.textTheme.labelMedium,
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
