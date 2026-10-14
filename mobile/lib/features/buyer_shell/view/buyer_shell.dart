import 'package:flutter/material.dart';

import '../../home/view/buyer_home_screen.dart';
import '../../marketplace/views/marketplace_screen.dart';
import '../../profile/view/profile_screen.dart';
import '../../transactions/views/transactions_screen.dart';

/// The signed-in shell: bottom navigation over the buyer-facing destinations.
///
/// Four destinations: Home, Marketplace, Transactions, Profile. Transactions
/// arrives now that the backend serves it (M5) — no disabled or "coming
/// soon" destination ever ships, so the fourth slot waited for this phase.
///
/// The screens are held in an [IndexedStack] rather than rebuilt on switch.
/// Rebuilding would discard the marketplace's scroll position and re-trigger its
/// initial load every time the buyer glanced at Home and came back, which for a
/// browse screen is the most likely interaction in the app.
class BuyerShell extends StatefulWidget {
  const BuyerShell({super.key});

  @override
  State<BuyerShell> createState() => _BuyerShellState();
}

class _BuyerShellState extends State<BuyerShell> {
  int _index = 0;

  /// The marketplace tab's position, named so the destinations stay readable
  /// and the index is not a bare `1` in a list of widgets.
  static const int _marketplaceIndex = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The screens supply their own `Scaffold` — including an `AppBar` — so
      // this one carries the `NavigationBar` alone. Nesting a second `Scaffold`
      // for the bar would give two competing body insets.
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          BuyerHomeScreen(
            onBrowseMarketplace: () =>
                setState(() => _index = _marketplaceIndex),
          ),
          const MarketplaceScreen(),
          const TransactionsScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int index) => setState(() => _index = index),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Marketplace',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Transactions',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
