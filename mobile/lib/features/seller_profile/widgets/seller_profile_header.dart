import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/seller_profile.dart';
import '../../../widgets/initials_avatar.dart';
import '../../../widgets/verified_seller_badge.dart';

/// The public profile header: avatar, name, conditional verification badge and
/// the barangay-level location.
///
/// The pale brand-green band is the approved "seller highlight" surface. The
/// avatar and the gaps step down on narrow screens so the name and location
/// keep their space instead of being squeezed by a fixed 80dp portrait.
class SellerProfileHeader extends StatelessWidget {
  const SellerProfileHeader({required this.profile, super.key});

  final SellerProfile profile;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ColoredBox(
      color: AppColors.primarySurface,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxWidth < 360;
          final double radius = compact ? 32 : 40;
          final double gap = compact ? AppSpacing.sm : AppSpacing.md;
          final double vertical = compact ? AppSpacing.md : AppSpacing.lg;

          return Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              vertical,
              AppSpacing.screenGutter,
              vertical,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                InitialsAvatar(
                  name: profile.name,
                  imageUrl: profile.avatarUrl,
                  radius: radius,
                ),
                SizedBox(width: gap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        profile.name,
                        style:
                            (compact
                                    ? theme.textTheme.titleLarge
                                    : theme.textTheme.headlineSmall)
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                  height: 1.2,
                                ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (profile.isVerified) ...<Widget>[
                        const SizedBox(height: AppSpacing.xs),
                        const VerifiedSellerBadge(),
                      ],
                      if (profile.hasPublicLocation) ...<Widget>[
                        const SizedBox(height: AppSpacing.xs),
                        _LocationLine(location: profile.publicLocation!.trim()),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Public location, reduced by the server to barangay/municipality/province.
class _LocationLine extends StatelessWidget {
  const _LocationLine({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const ExcludeSemantics(
          child: Padding(
            padding: EdgeInsets.only(top: AppSpacing.xxxs),
            child: Icon(
              Icons.location_on_outlined,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            location,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
