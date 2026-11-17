import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/seller_profile.dart';

/// The Profile tab: the public facts the server discloses, and only those.
///
/// Email, phone, the account's full address, verification documents and
/// administrative notes are deliberately absent — the model has no field for
/// them. Each row carries one icon, one label and one value, which keeps the
/// card scannable without turning it into a dashboard.
class SellerProfileDetailsTab extends StatelessWidget {
  const SellerProfileDetailsTab({
    required this.profile,
    required this.onRefresh,
    super.key,
  });

  final SellerProfile profile;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String memberSince = AppFormatters.formatMonthYear(
      profile.memberSince,
    );

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.md,
          AppSpacing.screenGutter,
          AppSpacing.xl,
        ),
        children: <Widget>[
          Text('Seller information', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            child: Column(
              children: <Widget>[
                _InfoRow(
                  icon: profile.isVerified
                      ? Icons.verified
                      : Icons.remove_circle_outline,
                  iconColor: profile.isVerified
                      ? AppColors.success
                      : AppColors.textSecondary,
                  label: 'Verification status',
                  value: profile.isVerified
                      ? 'Verified Seller'
                      : 'Not verified',
                  valueColor: profile.isVerified
                      ? AppColors.success
                      : AppColors.textSecondary,
                ),
                const _RowDivider(),
                _InfoRow(
                  icon: Icons.location_on_outlined,
                  iconColor: AppColors.primary,
                  label: 'Public location',
                  value: profile.hasPublicLocation
                      ? profile.publicLocation!.trim()
                      : 'Not provided',
                  valueColor: profile.hasPublicLocation
                      ? AppColors.text
                      : AppColors.textSecondary,
                ),
                const _RowDivider(),
                _InfoRow(
                  icon: Icons.calendar_today_outlined,
                  iconColor: AppColors.primary,
                  label: 'Member since',
                  value: memberSince.isEmpty ? 'Not recorded' : memberSince,
                  valueColor: memberSince.isEmpty
                      ? AppColors.textSecondary
                      : AppColors.text,
                ),
              ],
            ),
          ),
          if (profile.hasBio) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('About', style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    profile.bio!.trim(),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, thickness: 1, color: AppColors.border);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxxs),
              child: Icon(icon, size: 18, color: iconColor),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxxs),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: valueColor,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
