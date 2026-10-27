import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/transaction.dart';
import '../../../models/user.dart';
import '../../auth/state/auth_scope.dart';
import '../../auth/state/auth_state.dart';
import '../../inquiries/view/received_inquiries_screen.dart';
import '../../notifications/state/notifications_scope.dart';
import '../../seller_dashboard/view/seller_dashboard_view.dart';
import '../../seller_listings/view/seller_listings_screen.dart';
import '../../transactions/views/transactions_screen.dart';
import '../widgets/home_header.dart';

/// The Seller Mode landing screen.
///
/// The dashboard is built from `GET /seller/dashboard`, which resolves the
/// seller from the token. It shows the seller's own listing counts by status,
/// received-inquiry total, and transaction total plus pending count. Revenue,
/// conversion, and completed-transaction figures are deliberately not shown
/// because the API does not expose them.
///
/// Received Inquiries remains a pushed sub-screen rather than a sixth tab, and
/// My Listings and Transactions switch to their existing shell tabs.
class SellerHomeScreen extends StatefulWidget {
  const SellerHomeScreen({
    this.onOpenListings,
    this.onOpenProfile,
    this.onOpenTransactions,
    super.key,
  });

  /// Switches the shell to the My Listings tab.
  final VoidCallback? onOpenListings;

  /// Switches the shell to the Profile tab.
  final VoidCallback? onOpenProfile;

  /// Switches the shell to the Transactions tab.
  final VoidCallback? onOpenTransactions;

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
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                AppSpacing.xs,
                AppSpacing.screenGutter,
                AppSpacing.sm,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
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
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SellerDashboardView(
                    onOpenListings:
                        widget.onOpenListings ??
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (BuildContext context) =>
                                const SellerListingsScreen(),
                          ),
                        ),
                    onOpenInquiries: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) =>
                            const ReceivedInquiriesScreen(),
                      ),
                    ),
                    onOpenTransactions:
                        widget.onOpenTransactions ??
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (BuildContext context) =>
                                const TransactionsScreen(
                                  role: TransactionRole.seller,
                                ),
                          ),
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
