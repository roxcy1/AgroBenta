import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/popular_livestock_category.dart';
import '../state/popular_livestock_controller.dart';

/// Buyer Home's "Popular Livestock" section, above Recent Listings.
///
/// The ranking is real completed-sale data from the dedicated endpoint: no
/// views, no inquiries, no fabricated ordering. A category is tappable and
/// reuses the same marketplace category filter as the Home tiles and Browse
/// chips. With no completed sales in the window the section says so instead of
/// showing invented entries.
class PopularLivestockSection extends StatelessWidget {
  const PopularLivestockSection({
    required this.controller,
    required this.onSelectCategory,
    super.key,
  });

  final PopularLivestockController controller;

  /// Receives the canonical livestock type (e.g. `Cattle`).
  final ValueChanged<String> onSelectCategory;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenGutter,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Popular Livestock', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              _body(context, theme),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, ThemeData theme) {
    switch (controller.status) {
      case PopularLivestockStatus.initial:
      case PopularLivestockStatus.loading:
        return const SizedBox(
          height: 96,
          child: Center(child: CircularProgressIndicator()),
        );

      case PopularLivestockStatus.failed:
        return Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Could not load popular livestock.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton(onPressed: controller.load, child: const Text('Retry')),
          ],
        );

      case PopularLivestockStatus.ready:
        if (controller.categories.isEmpty) {
          return Text(
            'No completed sales yet. Popular livestock categories will appear '
            'here once purchases are completed.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          );
        }

        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            const double spacing = AppSpacing.sm;
            final double width = (constraints.maxWidth - spacing) / 2;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: <Widget>[
                for (final PopularLivestockCategory category
                    in controller.categories.take(4))
                  _PopularCategoryCard(
                    category: category,
                    width: width,
                    onTap: () => onSelectCategory(category.livestockType),
                  ),
              ],
            );
          },
        );
    }
  }
}

/// One category: representative listing photo (or livestock glyph), the
/// category name, the completed-sale count and an explicit Browse action.
class _PopularCategoryCard extends StatelessWidget {
  const _PopularCategoryCard({
    required this.category,
    required this.width,
    required this.onTap,
  });

  final PopularLivestockCategory category;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? photo = category.photoUrl;

    return SizedBox(
      width: width,
      child: Material(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: photo == null || photo.isEmpty
                        ? Container(
                            color: AppColors.surface,
                            child: const Icon(
                              Icons.pets_outlined,
                              color: AppColors.textSecondary,
                              size: 24,
                            ),
                          )
                        : Image.network(
                            photo,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: AppColors.surface,
                              child: const Icon(
                                Icons.pets_outlined,
                                color: AppColors.textSecondary,
                                size: 24,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        category.livestockType,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        category.salesLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Browse',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
