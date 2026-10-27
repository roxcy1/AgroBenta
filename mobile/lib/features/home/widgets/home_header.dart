import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/user.dart';
import '../../notifications/state/notifications_controller.dart';
import '../../notifications/state/notifications_scope.dart';
import '../../notifications/view/notifications_screen.dart';
import '../../../widgets/temporary_logo.dart';

/// The Home screen's header: brand on the left, notifications and the
/// account avatar on the right.
///
/// Not an [AppBar] — the design places the header inside the screen so the
/// landscape-style brand row leads the page, and it stays pinned above the
/// scroll so the bell and the avatar never require scrolling to reach.
///
/// The bell's unread badge is the real count from the session-scoped
/// [NotificationsController]; there are no decorative dots. The avatar uses
/// the account's `avatar_url` when one is set and the existing generic
/// initial treatment when it is not — no profile image is invented.
class HomeHeader extends StatelessWidget {
  const HomeHeader({required this.user, this.onOpenProfile, super.key});

  /// The authenticated user, for the avatar's fallback initial.
  final User user;

  /// Switches the shell to the Profile tab. Null omits the avatar action, so
  /// a standalone use of this screen never renders a dead control.
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          const TemporaryLogo(size: 40),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'AgroBenta',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                ),
                Text(
                  'Buy. Sell. Grow. Together.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const _NotificationsButton(),
          if (onOpenProfile != null)
            IconButton(
              tooltip: 'Profile',
              onPressed: onOpenProfile,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 48,
                minHeight: 48,
              ),
              icon: _Avatar(name: user.name, url: user.avatarUrl),
            ),
        ],
      ),
    );
  }
}

/// The notifications bell, with the live unread badge.
///
/// Reads [NotificationsScope] in `build`, so this rebuilds whenever the
/// notifications state changes — which is what keeps the badge current after
/// the Notifications screen marks items read.
class _NotificationsButton extends StatelessWidget {
  const _NotificationsButton();

  @override
  Widget build(BuildContext context) {
    final NotificationsController controller = NotificationsScope.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        final int unread = controller.state.unreadCount;
        return IconButton(
          tooltip: 'Notifications',
          icon: unread > 0
              ? Badge(
                  label: Text(unread > 99 ? '99+' : '$unread'),
                  child: const Icon(Icons.notifications_outlined),
                )
              : const Icon(Icons.notifications_outlined),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const NotificationsScreen(),
              ),
            );
          },
        );
      },
    );
  }
}

/// The account avatar: the user's photo when there is one, otherwise the
/// existing generic initial treatment.
///
/// Same rule as the profile screen's avatar — `avatar_url` is a server-held
/// field, and nothing here synthesises a URL or a picture.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.url});

  final String name;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final String? src = url;
    if (src == null || src.isEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: AppColors.primarySurface,
        child: Text(
          name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: 18,
      backgroundImage: NetworkImage(src),
    );
  }
}
