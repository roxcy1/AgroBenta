import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/conversation.dart';
import '../../../models/listing.dart';
import '../../../models/transaction.dart';
import '../../../models/user.dart';
import '../../auth/state/auth_scope.dart';
import '../../auth/state/auth_state.dart';
import '../../messaging/state/messaging_scope.dart';
import '../../messaging/view/chat_screen.dart';
import '../../notifications/state/notifications_scope.dart';
import '../../seller_dashboard/state/seller_activity_scope.dart';
import '../../seller_dashboard/view/all_activities_screen.dart';
import '../../seller_dashboard/view/seller_dashboard_view.dart';
import '../../seller_listings/state/seller_listing_scope.dart';
import '../../seller_listings/view/seller_listing_form_screen.dart';
import '../../seller_listings/view/seller_listings_screen.dart';
import '../../transactions/views/transaction_detail_screen.dart';
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
<<<<<<< Updated upstream
=======
/// Inquiries are delivered to the seller as messages (functional documentation
/// §8.2, MS-18), so there is no separate inquiry inbox: the inquiry count and
/// inquiry activities open the Messages tab. My Listings and Transactions
/// switch to their existing shell tabs.
>>>>>>> Stashed changes
class SellerHomeScreen extends StatefulWidget {
  const SellerHomeScreen({
    this.onOpenListings,
    this.onOpenMessages,
    this.onOpenProfile,
    this.onOpenTransactions,
    super.key,
  });

  /// Switches the shell to the My Listings tab.
  final VoidCallback? onOpenListings;

  /// Switches the shell to the Messages tab, where inquiries are read.
  final VoidCallback? onOpenMessages;

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

    /// The existing create-listing form, opened from Home. The My Listings list
    /// is refreshed afterwards so a draft created here appears in its tab.
    Future<void> addListing() async {
      await Navigator.of(context).push<Listing>(
        MaterialPageRoute<Listing>(
          builder: (BuildContext context) => const SellerListingFormScreen(),
          fullscreenDialog: true,
        ),
      );
      if (!context.mounted) {
        return;
      }
      await SellerListingScope.readOf(context).refresh();
    }

    void openMessages() {
      final VoidCallback? injected = widget.onOpenMessages;
      if (injected != null) {
        injected();
      }
    }

    /// Opens the buyer conversation behind an offer activity when the session
<<<<<<< Updated upstream
    /// already knows that pair; when no conversation exists yet there is
    /// nothing to open, so this is a no-op.
=======
    /// already knows that pair; otherwise switches to Messages, where the
    /// inquiry and its buyer live.
>>>>>>> Stashed changes
    void openOfferActivity(int buyerId, int? transactionId) {
      final conversations = MessagingScope.readOf(
        context,
      ).state.conversations;
      Conversation? match;
      for (final Conversation conversation in conversations) {
        if (conversation.counterpart.id == buyerId) {
          match = conversation;
          break;
        }
      }

      if (match == null) {
<<<<<<< Updated upstream
=======
        openMessages();
>>>>>>> Stashed changes
        return;
      }

      final Conversation conversation = match;
      final int currentUserId = AuthScope.of(context).state.user?.id ?? 0;
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => ChatScreen(
            counterpart: conversation.counterpart,
            currentUserId: currentUserId,
            counterpartRole: 'Buyer',
          ),
        ),
      );
    }

    void openTransactionActivity(int transactionId) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              TransactionDetailScreen(transactionId: transactionId),
        ),
      );
    }

    void openListings() {
      final VoidCallback? injected = widget.onOpenListings;
      if (injected != null) {
        injected();
        return;
      }
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const SellerListingsScreen(),
        ),
      );
    }

    void openTransactions() {
      final VoidCallback? injected = widget.onOpenTransactions;
      if (injected != null) {
        injected();
        return;
      }
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const TransactionsScreen(
            role: TransactionRole.seller,
          ),
        ),
      );
    }

    void openAllActivities() {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => AllActivitiesScreen(
<<<<<<< Updated upstream
=======
            onOpenMessages: openMessages,
>>>>>>> Stashed changes
            onOpenListings: openListings,
            onOpenTransactions: openTransactions,
            onOpenOffer: openOfferActivity,
            onOpenTransaction: openTransactionActivity,
          ),
        ),
      );
    }

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
                    onAddListing: addListing,
                    activityRepository: SellerActivityScope.readOf(context),
                    onOpenOffer: openOfferActivity,
                    onOpenTransaction: openTransactionActivity,
                    onOpenListings: openListings,
<<<<<<< Updated upstream
=======
                    onOpenMessages: openMessages,
>>>>>>> Stashed changes
                    onOpenTransactions: openTransactions,
                    onSeeAllActivities: openAllActivities,
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
