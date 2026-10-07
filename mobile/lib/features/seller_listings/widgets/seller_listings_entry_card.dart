import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../models/user.dart';
import '../view/seller_listings_screen.dart';

/// The seller's entry point into listing management, on the Home screen.
///
/// **Shown only when [User.isSeller] is true**, and that value comes from
/// `/auth/me` — the server's own statement about the account, never something
/// the app infers from a verification record. Two sources of truth for one fact
/// would eventually disagree, and the wrong answer either hides a real feature
/// from a seller or offers one to a buyer whose every request would be refused
/// with a `403`.
///
/// In context on Home rather than in the bottom navigation. `mobile/DESIGN.md` is
/// explicit that navigation must not be built for screens a user cannot reach, and
/// My Listings is by definition unreachable for a buyer: the route requires the
/// approved-seller capability. A permanent tab would sit there answering `403`.
///
/// No count and no request. This card is a link, and making it load the list just
/// to show a number would turn a navigation element into a request on every Home
/// build.
class SellerListingsEntryCard extends StatelessWidget {
  const SellerListingsEntryCard({required this.user, super.key});

  final User user;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (!user.isSeller) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('My Listings', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Create a listing, submit it for review, and manage the ones you '
              'have already put up.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              // The button's own context, not a field on the widget: a
              // `StatelessWidget` has none, and the builder's is guaranteed to be
              // a descendant of the `Navigator`.
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      const SellerListingsScreen(),
                ),
              ),
              icon: const Icon(Icons.storefront_outlined, size: 18),
              label: const Text('Manage my listings'),
            ),
          ],
        ),
      ),
    );
  }
}
