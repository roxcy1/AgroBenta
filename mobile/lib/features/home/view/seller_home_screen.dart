import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/user.dart';
import '../../auth/state/auth_scope.dart';
import '../../auth/state/auth_state.dart';
import '../../notifications/state/notifications_scope.dart';
import '../../seller_listings/widgets/seller_listings_entry_card.dart';
import '../widgets/home_header.dart';

/// The Seller Mode landing screen.
///
/// This is deliberately a small, truthful hub rather than a dashboard: the
/// backend exposes no seller metrics or received-inquiries endpoint, so no
/// counts, charts or inquiry records are fabricated here. It shows the real
/// account, the notification bell and the existing My Listings entry, whose
/// action switches the shell to the My Listings tab.
class SellerHomeScreen extends StatefulWidget {
  const SellerHomeScreen({this.onOpenListings, this.onOpenProfile, super.key});

  /// Switches the shell to the My Listings tab.
  final VoidCallback? onOpenListings;

  /// Switches the shell to the Profile tab.
  final VoidCallback? onOpenProfile;

  @override
  State<SellerHomeScreen> createState() => _SellerHomeScreenState();
}

class _SellerHomeScreenState extends State<SellerHomeScreen> {
  @override
  void initState() {
    super.initState();
    // The header's badge reads the session controller, which starts empty.
    // Refreshing on entry is the same pattern BuyerHomeScreen uses.
    NotificationsScope.readOf(context).refreshUnreadCount();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AuthState state = AuthScope.of(context).state;
    final User? user = state.user;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Home')),
        body: SafeArea(
          child: Center(
            child: Text('No account loaded.', style: theme.textTheme.bodySmall),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            HomeHeader(user: user, onOpenProfile: widget.onOpenProfile),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.screenGutter,
                            AppSpacing.xs,
                            AppSpacing.screenGutter,
                            0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Seller Mode',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                'Hello, ${user.name}!',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                'Manage your livestock listings and sales.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.screenGutter,
                          ),
                          child: SellerListingsEntryCard(
                            user: user,
                            onManage: widget.onOpenListings,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
