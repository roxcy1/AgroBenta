import 'package:flutter/material.dart';

import '../../../models/transaction.dart';
import '../../home/view/buyer_home_screen.dart';
import '../../marketplace/views/marketplace_screen.dart';
import '../../messaging/state/conversations_controller.dart';
import '../../messaging/state/messaging_scope.dart';
import '../../messaging/view/conversations_screen.dart';
import '../../profile/view/profile_screen.dart';
import '../../transactions/views/transactions_screen.dart';

/// The signed-in shell: bottom navigation over the buyer-facing destinations.
///
/// Five destinations, in the order the mobile design fixes: Home, Browse,
/// Messages, Transactions, Profile. Messages carries a live unread badge driven
/// by the session-scoped [ConversationsController] installed in `main.dart`.
///
/// The screens are held in an [IndexedStack] rather than rebuilt on switch.
/// Rebuilding would discard the marketplace's scroll position and re-trigger
/// its initial load every time the buyer glanced at Home and came back, which
/// for a browse screen is the most likely interaction in the app.
class BuyerShell extends StatefulWidget {
  const BuyerShell({super.key});

  @override
  State<BuyerShell> createState() => _BuyerShellState();
}

class _BuyerShellState extends State<BuyerShell> {
  int _index = 0;

  /// The Browse tab's position, named so the destinations stay readable and the
  /// index is not a bare `1` in a list of widgets.
  static const int _browseIndex = 1;

  /// The profile tab's position, for the Home header's avatar action.
  static const int _profileIndex = 4;

  @override
  Widget build(BuildContext context) {
    // Reading the controller here registers a dependency on `MessagingScope`,
    // so this shell rebuilds whenever the inbox state changes. That is what
    // makes the unread badge on the Messages tab update live.
    final ConversationsController messaging = MessagingScope.of(context);
    final int unread = messaging.state.totalUnread;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          BuyerHomeScreen(
            onBrowseMarketplace: () => setState(() => _index = _browseIndex),
            onOpenProfile: () => setState(() => _index = _profileIndex),
          ),
          const MarketplaceScreen(),
          const ConversationsScreen(),
          const TransactionsScreen(role: TransactionRole.buyer),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int index) => setState(() => _index = index),
        destinations: <NavigationDestination>[
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Browse',
          ),
          // Messages, with the unread count as an icon badge. The count is
          // read from the ConversationsController watched above; the badge
          // uses Material 3's built-in `Badge` widget rather than a custom
          // one because it handles RTL, sizing and semantics correctly.
          NavigationDestination(
            icon: unread > 0
                ? Badge(
                    label: Text(unread > 99 ? '99+' : '$unread'),
                    child: const Icon(Icons.chat_bubble_outline),
                  )
                : const Icon(Icons.chat_bubble_outline),
            selectedIcon: unread > 0
                ? Badge(
                    label: Text(unread > 99 ? '99+' : '$unread'),
                    child: const Icon(Icons.chat_bubble),
                  )
                : const Icon(Icons.chat_bubble),
            label: 'Messages',
          ),
          const NavigationDestination(
            icon: Icon(Icons.swap_horiz_outlined),
            selectedIcon: Icon(Icons.swap_horiz),
            label: 'Transactions',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
