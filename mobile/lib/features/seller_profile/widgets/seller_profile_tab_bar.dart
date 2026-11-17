import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../state/seller_profile_state.dart';

/// Keys for the two tabs, so layout tests can measure their equal share of the
/// row without depending on label text.
const ValueKey<String> sellerProfileTabProfileKey = ValueKey<String>(
  'seller-profile-tab-profile',
);
const ValueKey<String> sellerProfileTabListingsKey = ValueKey<String>(
  'seller-profile-tab-listings',
);

/// The Profile / Listings tabs.
///
/// Each tab takes exactly half the available width and the whole row is a
/// 52dp touch band. The selected tab is bold emerald with a full-width 3dp
/// underline; the inactive tab is muted. The row is deliberately un-padded, so
/// the 50/50 split is a real half of the screen rather than a half of an inset
/// content area.
class SellerProfileTabBar extends StatelessWidget {
  const SellerProfileTabBar({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final SellerProfileTab selected;
  final ValueChanged<SellerProfileTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _Tab(
              key: sellerProfileTabProfileKey,
              label: 'Profile',
              icon: Icons.person_outline,
              selected: selected == SellerProfileTab.profile,
              onTap: () => onSelected(SellerProfileTab.profile),
            ),
          ),
          Expanded(
            child: _Tab(
              key: sellerProfileTabListingsKey,
              label: 'Listings',
              icon: Icons.grid_view_outlined,
              selected: selected == SellerProfileTab.listings,
              onTap: () => onSelected(SellerProfileTab.listings),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = selected ? AppColors.primary : AppColors.textSecondary;

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              ExcludeSemantics(child: Icon(icon, size: 18, color: color)),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
