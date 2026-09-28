import 'package:flutter/material.dart';

import '../../home/view/buyer_home_screen.dart';
import '../../marketplace/views/marketplace_screen.dart';

/// The signed-in shell: bottom navigation over the buyer-facing destinations.
///
/// ## Two destinations, not five
///
/// `mobile/DESIGN.md` asks for 3–5 bottom-nav items across the app's life, and
/// M2 has delivered exactly two of them: Home and Marketplace. Transactions,
/// Notifications and Profile are later phases, and a disabled or "coming soon"
/// destination is worse than an absent one — it advertises a screen that cannot
/// be opened and reads as a broken build. Two items is a valid `NavigationBar`
/// and the third slot costs nothing when the features exist.
///
/// The two screens are held in an [IndexedStack] rather than rebuilt on switch.
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
            onBrowseMarketplace: () => setState(() => _index = _marketplaceIndex),
          ),
          const MarketplaceScreen(),
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
        ],
      ),
    );
  }
}
