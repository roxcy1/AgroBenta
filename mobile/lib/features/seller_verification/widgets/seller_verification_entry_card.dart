import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/seller_verification.dart';
import '../../../models/user.dart';
import '../state/seller_verification_controller.dart';
import '../state/seller_verification_scope.dart';
import '../state/seller_verification_state.dart';
import '../view/seller_verification_screen.dart';

/// The seller card on the Home screen: current capability, and the way into the
/// verification flow.
///
/// It answers "am I a seller, and where is my application?" without a second tap,
/// and it is the single "Become a Seller" entry point in the app.
///
/// ## The capability is not inferred here
///
/// [User.isSeller] comes from `/auth/me` and is the only thing that decides
/// whether a seller is offered the form. The verification status is a separate
/// fact about an application, and the two are shown separately on purpose — a
/// seller whose latest application was somehow rejected should not be told to
/// apply again, because the account is already a seller and the submission would
/// be refused with a `403`.
class SellerVerificationEntryCard extends StatefulWidget {
  const SellerVerificationEntryCard({required this.user, super.key});

  final User user;

  @override
  State<SellerVerificationEntryCard> createState() =>
      _SellerVerificationEntryCardState();
}

class _SellerVerificationEntryCardState
    extends State<SellerVerificationEntryCard> {
  late final SellerVerificationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SellerVerificationScope.readOf(context);
    // Only the first time. `load` is guarded, and asking again on every rebuild
    // would turn a card into a request generator.
    if (_controller.state.status == SellerVerificationUiStatus.initial) {
      _controller.load();
    }
  }

  void _openVerification() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const SellerVerificationScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? child) {
        final SellerVerificationState state = _controller.state;
        final bool isSeller = widget.user.isSeller;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Sell on AgroBenta', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  isSeller
                      ? 'Your account is a seller.'
                      : 'Apply to sell. An administrator reviews every '
                            'application, and your account becomes a seller only '
                            'after approval.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                _statusLine(state),
                const SizedBox(height: AppSpacing.md),
                _action(state, isSeller: isSeller),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The one-line application status, or nothing while it is unknown.
  ///
  /// Silent while loading rather than showing a spinner in a card the user is
  /// reading: the account type beside it is already known, and the application
  /// status arriving a moment later is not worth a flicker.
  Widget _statusLine(SellerVerificationState state) {
    final SellerVerification? verification = state.verification;
    if (verification == null) {
      return const SizedBox.shrink();
    }

    final (Color color, String text) = switch (verification.status) {
      SellerVerificationStatus.approved => (
        AppColors.success,
        'Verification approved',
      ),
      SellerVerificationStatus.rejected => (
        AppColors.error,
        'Verification not approved',
      ),
      SellerVerificationStatus.submitted ||
      SellerVerificationStatus.pendingReview => (
        AppColors.warning,
        'Verification under review',
      ),
    };

    return Row(
      children: <Widget>[
        // The colour is a supporting signal only; the words beside it are what
        // actually carry the state.
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }

  /// The single action, whose label follows the state.
  ///
  /// A seller is never offered the form: the account already has capability, and
  /// the endpoint would answer `403`. They get a way to view the record instead.
  Widget _action(SellerVerificationState state, {required bool isSeller}) {
    if (state.status == SellerVerificationUiStatus.loading) {
      return const OutlinedButton(
        onPressed: null,
        child: Text('Checking your application…'),
      );
    }

    if (state.status == SellerVerificationUiStatus.failed) {
      return OutlinedButton(
        onPressed: _controller.load,
        child: const Text('Try again'),
      );
    }

    if (isSeller) {
      return OutlinedButton(
        onPressed: _openVerification,
        child: const Text('View verification'),
      );
    }

    // One button, labelled for what pressing it actually does. "Become a Seller"
    // for someone who has never applied, "Resubmit Verification" for someone
    // whose application was declined, and a read-only "View status" while one is
    // open — which is the state where a second application would be refused.
    return switch (state.status) {
      SellerVerificationUiStatus.notSubmitted => FilledButton(
        onPressed: _openVerification,
        child: const Text('Become a Seller'),
      ),
      SellerVerificationUiStatus.rejected => FilledButton(
        onPressed: _openVerification,
        child: const Text('Resubmit Verification'),
      ),
      _ => OutlinedButton(
        onPressed: _openVerification,
        child: const Text('View status'),
      ),
    };
  }
}
