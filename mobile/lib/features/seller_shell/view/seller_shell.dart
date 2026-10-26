import 'package:flutter/material.dart';

import '../../../models/transaction.dart';
import '../../home/view/seller_home_screen.dart';
import '../../messaging/state/conversations_controller.dart';
import '../../messaging/state/messaging_scope.dart';
import '../../messaging/view/conversations_screen.dart';
import '../../profile/view/profile_screen.dart';
import '../../seller_listings/view/seller_listings_screen.dart';
import '../../transactions/views/transactions_screen.dart';

/// The Seller Mode shell: bottom navigation over the seller-facing
/// destinations.
///
/// Five destinations, in the order this phase fixes: Home, My Listings,
/// Messages, Transactions, Profile. It is only ever built for an account whose
/// server-granted capability is `seller`; `AccountModeShell` enforces that and
/// falls back to BuyerShell. The backend still authorises every request, so the
/// shell itself grants nothing.
///
/// The screens are held in an [IndexedStack] for the same reason the buyer
/// shell does: switching tabs must not discard the seller's loaded listings or
/// scroll position.
class SellerShell extends StatefulWidget {
  const SellerShell({super.key});

  @override
  State<SellerShell> createState() => _SellerShellState();
}

class _SellerShellState extends State<SellerShell> {
  int _index = 0;

  static const int _listingsIndex = 1;
  static const int _transactionsIndex = 3;
  static const int _profileIndex = 4;

  @override
  Widget build(BuildContext context) {
    final ConversationsController messaging = MessagingScope.of(context);
    final int unread = messaging.state.totalUnread;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          SellerHomeScreen(
            onOpenListings: () => setState(() => _index = _listingsIndex),
            onOpenProfile: () => setState(() => _index = _profileIndex),
            onOpenTransactions: () =>
                setState(() => _index = _transactionsIndex),
          ),
          const SellerListingsScreen(),
          const ConversationsScreen(),
          const TransactionsScreen(role: TransactionRole.seller),
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
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'My Listings',
          ),
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
