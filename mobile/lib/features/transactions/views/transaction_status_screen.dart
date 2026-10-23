import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/message.dart';
import '../../../models/transaction.dart';
import '../../auth/state/auth_scope.dart';
import '../../marketplace/widgets/marketplace_state_views.dart';
import '../../messaging/view/chat_screen.dart';
import '../state/transaction_detail_controller.dart';
import '../state/transaction_detail_state.dart';
import '../state/transaction_scope.dart';
import 'transaction_status_content.dart';

/// The buyer-facing **Transaction Status** screen.
///
/// A distinct screen from `TransactionDetailScreen`: it presents the current
/// status and a progress tracker for the same record, reached from the detail
/// screen. It reuses [TransactionDetailController] and therefore the same
/// `GET /transactions/{id}` call — there is no separate "status" endpoint, and
/// none is invented.
///
/// The tracker reflects the real workflow only. The backend keeps one current
/// `status` and no per-step history, so a dated timeline is not available and
/// is not faked; [TransactionStatusContent] states that plainly.
class TransactionStatusScreen extends StatelessWidget {
  const TransactionStatusScreen({required this.transactionId, super.key});

  final int transactionId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction Status')),
      body: SafeArea(child: _StatusBody(transactionId: transactionId)),
    );
  }
}

class _StatusBody extends StatefulWidget {
  const _StatusBody({required this.transactionId});

  final int transactionId;

  @override
  State<_StatusBody> createState() => _StatusBodyState();
}

class _StatusBodyState extends State<_StatusBody> {
  late final TransactionDetailController _controller;

  @override
  void initState() {
    super.initState();
    // Reused verbatim: this screen only reads, so the controller's cancel
    // machinery is simply never invoked.
    _controller = TransactionDetailController(
      TransactionScope.readOf(context),
      widget.transactionId,
    );
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? child) {
        final TransactionDetailState state = _controller.state;

        if (state.isLoading) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: AppSpacing.md),
                Text('Loading status'),
              ],
            ),
          );
        }

        // A 404 covers both "does not exist" and "not a party" — and, since a
        // revoked token also fails owner-scoping, the unauthorized case lands
        // here too. The server declines to distinguish, so neither does the app.
        if (state.isUnavailable) {
          return const _UnavailableNotice();
        }

        if (state.status == TransactionDetailStatus.failed) {
          return MarketplaceErrorState(
            title: 'Could not load status',
            message: state.errorMessage ?? 'Something went wrong.',
            onRetry: _controller.load,
          );
        }

        final Transaction? transaction = state.transaction;
        if (transaction == null) {
          return const SizedBox.shrink();
        }

        return TransactionStatusContent(
          transaction: transaction,
          onMessageSeller: () => _openThread(context, transaction),
        );
      },
    );
  }

  /// Opens the existing chat thread with the counterparty, exactly as the
  /// detail screen does: the id comes from the payload, so it routes to a real,
  /// server-identifiable user, never an invented one. If there is no session id
  /// the action is honest about why it cannot proceed instead of failing.
  void _openThread(BuildContext context, Transaction transaction) {
    final int? viewerId = AuthScope.maybeOf(context)?.state.user?.id;
    if (viewerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in again to message the seller.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ChatScreen(
          counterpart: ChatUser(
            id: transaction.counterparty.id,
            name: transaction.counterparty.name,
            avatarUrl: null,
          ),
          currentUserId: viewerId,
          listingId: transaction.listing.id,
        ),
      ),
    );
  }
}

/// Shown when the record is not visible to this user.
///
/// A `404` here means the transaction does not exist, or the caller is not a
/// party to it — and a revoked/unauthorized token fails the same ownership
/// check. The backend declines to say which, so the app must not guess either.
class _UnavailableNotice extends StatelessWidget {
  const _UnavailableNotice();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.visibility_off_outlined,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'This status is not available',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'This transaction may not exist, or you may not be a party to '
              'it.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back to transactions'),
            ),
          ],
        ),
      ),
    );
  }
}
