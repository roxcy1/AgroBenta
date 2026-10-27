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
import 'transaction_detail_content.dart';
import 'transaction_status_screen.dart';

/// One transaction's detail, from `GET /transactions/{id}`.
///
/// Takes a [transactionId] and nothing else. The list object is deliberately
/// not passed in: the whole point of re-fetching is that a transaction may
/// have left `pending` since it was listed, and seeding the screen with the
/// list copy would show a stale state for a moment.
///
/// There is deliberately **no "Mark complete" affordance**. The backend
/// answers that transition with 501 (OQ-15) and the client hides it entirely
/// — a button that always errors is worse than no button.
class TransactionDetailScreen extends StatelessWidget {
  const TransactionDetailScreen({required this.transactionId, super.key});

  final int transactionId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction Details')),
      body: SafeArea(child: _DetailBody(transactionId: transactionId)),
    );
  }
}

class _DetailBody extends StatefulWidget {
  const _DetailBody({required this.transactionId});

  final int transactionId;

  @override
  State<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends State<_DetailBody> {
  late final TransactionDetailController _controller;

  @override
  void initState() {
    super.initState();
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
                Text('Loading transaction'),
              ],
            ),
          );
        }

        if (state.isUnavailable) {
          return const _UnavailableNotice();
        }

        if (state.status == TransactionDetailStatus.failed) {
          return MarketplaceErrorState(
            title: 'Could not load transaction',
            message: state.errorMessage ?? 'Something went wrong.',
            onRetry: _controller.load,
          );
        }

        final Transaction? transaction = state.transaction;
        if (transaction == null) {
          return const SizedBox.shrink();
        }

        return TransactionDetailContent(
          transaction: transaction,
          isCancelling: state.isCancelling,
          cancelErrorMessage: state.cancelErrorMessage,
          canCancel: state.canCancel,
          onCancel: () => _confirmCancel(transaction),
          onDismissCancelError: _controller.clearCancelError,
          onMessageCounterparty: () => _openThread(context, transaction),
          onViewStatus: () => _openStatus(context, transaction),
        );
      },
    );
  }

  /// Opens the dedicated status screen for this same record, by id.
  void _openStatus(BuildContext context, Transaction transaction) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            TransactionStatusScreen(transactionId: transaction.id),
      ),
    );
  }

  /// Opens the existing chat thread with the counterparty.
  ///
  /// The counterparty id comes straight from the payload: it is the seller for
  /// a buyer and the buyer for a seller, so this routes to a real,
  /// server-identifiable user. `ChatScreen` reads `MessagingScope` in its own
  /// `initState`, so this screen builds without one — the same split
  /// `ListingDetailScreen` uses.
  void _openThread(BuildContext context, Transaction transaction) {
    final int? viewerId = AuthScope.maybeOf(context)?.state.user?.id;
    if (viewerId == null) {
      // Without a session id the chat cannot label its own messages correctly,
      // so the action is not offered as if it would work.
      final String counterparty = transaction.role == TransactionRole.seller
          ? 'buyer'
          : 'seller';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign in again to message the $counterparty.')),
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

  /// Confirms before calling: the transition is irreversible.
  Future<void> _confirmCancel(Transaction transaction) async {
    final bool isSeller = transaction.role == TransactionRole.seller;
    final String recordNoun = isSeller ? 'sale' : 'request';

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Cancel this $recordNoun?'),
        content: Text(
          'This cannot be undone. A cancelled $recordNoun stays cancelled.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Keep $recordNoun'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text('Cancel $recordNoun'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _controller.cancel();
    }
  }
}

/// Shown when the transaction is not visible to this user.
///
/// Fixed copy, no server string. A `404` here means the transaction does not
/// exist or the caller is not a party to it, and the backend declines to say
/// which — so the app must not guess either.
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
              'This transaction is not available',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'It may not exist, or you may not be a party to it.',
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
