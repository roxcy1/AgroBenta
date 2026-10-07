import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/user.dart';
import '../../auth/state/auth_scope.dart';
import '../../auth/state/auth_state.dart';
import '../../auth/widgets/auth_error_banner.dart';
import '../../seller_listings/widgets/seller_listings_entry_card.dart';
import '../../seller_verification/widgets/seller_verification_entry_card.dart';

/// The authenticated landing screen.
///
/// A shell, and honestly so. The buyer shell's bottom navigation carries the app
/// between Home and the Marketplace; this screen states what the account is, says
/// where the account is in the seller verification flow, and offers a way into
/// the marketplace. Transactions, notifications and messaging are later phases,
/// and `mobile/DESIGN.md` is explicit that navigation must not be built for
/// screens that do not exist — so nothing here points at them, and no placeholder
/// listings are invented to fill the space.
///
/// Listing management is here for sellers only, as a card in this screen's
/// scroll rather than a tab in the bottom navigation: the navigation is shared
/// with every buyer, and a tab that leads to a screen the buyer cannot use is
/// exactly what the design rules forbid.
class BuyerHomeScreen extends StatelessWidget {
  const BuyerHomeScreen({this.onBrowseMarketplace, super.key});

  /// Switches the shell to the Marketplace tab.
  ///
  /// Injected rather than reached for, so this screen does not have to know how
  /// the shell is built or hold a reference to it. Null renders the card without
  /// the button, which is what a test or a standalone use of this screen wants.
  final VoidCallback? onBrowseMarketplace;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AuthState state = AuthScope.of(context).state;
    final User? user = state.user;

    // A signed-in state always carries a user. Rendering nothing rather than
    // crashing keeps a contract surprise from becoming a red screen.
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
      appBar: AppBar(
        title: const Text('Home'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: TextButton(
              onPressed: state.isSigningOut ? null : () => _signOut(context),
              style: TextButton.styleFrom(
                // The app bar is the brand green, and the global text-button
                // theme is also brand green — the default here is green text on
                // a green bar. White is the fix, stated locally so a future
                // change to the app bar colour is visible in one place.
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white70,
              ),
              child: state.isSigningOut
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Sign out'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Hello, ${user.name}!',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Happy trading!',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (state.errorMessage != null) ...<Widget>[
                    AuthErrorBanner(message: state.errorMessage!),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Your account',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _AccountRow(label: 'Name', value: user.name),
                          _AccountRow(label: 'Email', value: user.email),
                          const SizedBox(height: AppSpacing.md),
                          _CapabilityRow(user: user),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SellerVerificationEntryCard(user: user),
                  // Seller-only, and only when `/auth/me` says the account is a
                  // seller. A buyer never sees it, which is also why My Listings
                  // is not a tab in the bottom navigation: the tab would exist
                  // for them and lead to a screen whose every request is a 403.
                  if (user.isSeller) ...<Widget>[
                    const SizedBox(height: AppSpacing.lg),
                    SellerListingsEntryCard(user: user),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Browse the marketplace',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Search and filter active livestock listings, and '
                            'open one to see its full details.',
                            style: theme.textTheme.bodySmall,
                          ),
                          if (onBrowseMarketplace != null) ...<Widget>[
                            const SizedBox(height: AppSpacing.md),
                            OutlinedButton(
                              onPressed: onBrowseMarketplace,
                              child: const Text('Go to marketplace'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signOut(BuildContext context) =>
      AuthScope.of(context).signOut();
}

/// A label and its value, stacked. Truncates rather than wrapping a long
/// value into an unreadable block.
class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            value,
            style: theme.textTheme.bodyLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// The account's seller capability, as the server decided it.
///
/// The word carries the meaning and the chip is only a frame, so the state is
/// still readable without colour. This app cannot grant seller capability — it
/// is changed by the server when an administrator approves a verification — so
/// this row reflects, and never changes, what `/auth/me` returned. The seller
/// card below carries the application itself, which is a separate fact.
class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Expanded(
          child: Text('Account type', style: theme.textTheme.labelMedium),
        ),
        Chip(label: Text(user.isSeller ? 'Seller' : 'Buyer')),
      ],
    );
  }
}
