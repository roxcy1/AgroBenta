import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/conversation.dart';
import '../../../models/message.dart';
import '../../../models/offer.dart';
import '../../offers/state/chat_offers_controller.dart';
import '../../offers/state/offer_scope.dart';
import '../../offers/state/offer_state.dart';
import '../../offers/view/make_offer_screen.dart';
import '../../offers/widgets/chat_offer_panel.dart';
import '../../transactions/views/transaction_detail_screen.dart';
import '../state/chat_controller.dart';
import '../state/messaging_scope.dart';
import '../state/messaging_state.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/message_bubble.dart';

/// One chat thread with a counterpart.
///
/// Creates its own [ChatController] in `initState` and disposes it on unmount.
///
/// ## Why `currentUserId` is a constructor parameter
///
/// `AuthScope.of(context)` cannot be called from `initState` — Dart forbids
/// registering an inherited-widget dependency before `initState` completes.
/// The caller already knows the current user's id from the session, so it is
/// passed in rather than looked up here. That also makes this screen testable
/// without standing up an `AuthScope`.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.counterpart,
    required this.currentUserId,
    this.listingId,
    this.offerInquiry,
    this.counterpartRole,
    super.key,
  });

  /// The other user in the thread.
  final ChatUser counterpart;

  /// The caller's user id — from the authenticated session, passed by the
  /// caller because [AuthScope] cannot be reached from `initState`.
  final int currentUserId;

  /// The listing this thread is about, if any.
  final int? listingId;

  /// The server-provided inquiry the seller can still answer with an offer.
  ///
  /// `null` for the buyer side, for a thread with no open inquiry, and for
  /// chats opened outside Messages — the action is only offered where the
  /// server said it is eligible.
  final ConversationEligibleInquiry? offerInquiry;

  /// The counterpart's role in this thread (`Buyer`/`Seller`), when the
  /// conversation has exactly one side. `null` means "do not guess".
  final String? counterpartRole;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatController _controller;
  late final ChatOffersController _offers;

  @override
  void initState() {
    super.initState();
    // `readRepositoryOf` uses `getInheritedWidgetOfExactType` — no dependency
    // is registered, so it is safe from `initState`.
    final repository = MessagingScope.readRepositoryOf(context);

    _controller = ChatController(
      repository,
      counterpartId: widget.counterpart.id,
      currentUserId: widget.currentUserId,
      listingId: widget.listingId,
    );
    _controller.load();
    // Mark read on open — the user is looking at the thread, so unread
    // messages are read from their perspective.
    _controller.markRead();

    // The offer panel is per-thread state. The list is scoped by counterpart
    // because a conversation is the buyer–seller pair, not one listing.
    _offers = ChatOffersController(
      OfferScope.readOf(context),
      counterpartId: widget.counterpart.id,
    );
    _offers.load();
  }

  @override
  void dispose() {
    _offers.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _onSend(String body) => _controller.send(body);

  /// Opens the seller's offer form for the eligible inquiry, then refreshes
  /// this thread's offer panel when an offer was actually created.
  Future<void> _openMakeOffer(ConversationEligibleInquiry inquiry) async {
    final int? listingId = inquiry.listingId;
    if (listingId == null) {
      return;
    }

    final bool? created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => MakeOfferScreen.forConversation(
          inquiryId: inquiry.id,
          listingId: listingId,
          buyerName: widget.counterpart.name,
          listingTitle: inquiry.listingTitle,
          askingPrice: inquiry.askingPrice,
          photoUrl: inquiry.photoUrl,
          paymentMethod: inquiry.paymentMethod,
          collectionMethod: inquiry.collectionMethod,
          preferredSchedule: inquiry.preferredSchedule,
        ),
      ),
    );

    if (created == true && mounted) {
      await _offers.load();
    }
  }

  /// Shows the transaction the acceptance created, with the one honest link
  /// the app can offer. An already-accepted offer loaded from the list cannot
  /// be linked: `OfferResource` carries no transaction id.
  Future<void> _acceptOffer(Offer offer) async {
    final OfferAcceptance? result = await _offers.accept(offer);
    if (result == null || !mounted) {
      return;
    }

    final String amount =
        AppFormatters.formatMoney(result.offer.proposedAmount) ??
        result.offer.proposedAmount;
    final bool? view = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Offer accepted'),
        content: Text(
          'A pending transaction for $amount was created. '
          'The seller will see it in My Sales.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('View transaction'),
          ),
        ],
      ),
    );

    if (view == true && mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              TransactionDetailScreen(transactionId: result.transaction.id),
        ),
      );
    }
  }

  Future<void> _declineOffer(Offer offer) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Decline this offer?'),
        content: const Text(
          'The offer will be declined and cannot be accepted later. '
          'The seller can still make a new offer.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep offer'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _offers.decline(offer);
    }
  }

  Future<void> _withdrawOffer(Offer offer) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Withdraw this offer?'),
        content: const Text(
          'The buyer will no longer be able to accept it. '
          'You can make a new offer afterwards.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep offer'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _offers.withdraw(offer);
    }
  }

  void _showProfile() {
    final ChatUser user = widget.counterpart;
    final String? role = widget.counterpartRole;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.xs,
              AppSpacing.screenGutter,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _ProfileAvatar(user: user),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(user.name, style: theme.textTheme.titleLarge),
                          if (role != null) ...<Widget>[
                            const SizedBox(height: 2),
                            Text(
                              role,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Only the profile details AgroBenta shares with chat '
                  'participants are shown here.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? role = widget.counterpartRole;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: _showProfile,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: 4,
            ),
            child: Row(
              children: <Widget>[
                _SmallAvatar(user: widget.counterpart),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        widget.counterpart.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (role != null)
                        Text(
                          role,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[_controller, _offers]),
          builder: (BuildContext context, Widget? child) {
            final ChatState state = _controller.state;
            final ChatOffersState offers = _offers.state;

            // A send error is shown as a snackbar, once.
            final String? sendError = state.sendErrorMessage;
            if (sendError != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(sendError)));
                _controller.clearSendError();
              });
            }

            // An offer action failure is shown the same way, once.
            final String? offerError = offers.actionErrorMessage;
            if (offerError != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(offerError)));
                _offers.clearActionError();
              });
            }

            return Column(
              children: <Widget>[
                Expanded(
                  child: switch (state.status) {
                    ChatStatus.initial || ChatStatus.loading => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    ChatStatus.failed => _ErrorState(
                      message: state.errorMessage ?? 'Something went wrong.',
                      onRetry: _controller.load,
                    ),
                    _ =>
                      state.messages.isEmpty
                          ? const _EmptyThread()
                          : _MessageList(
                              messages: state.messages,
                              currentUserId: widget.currentUserId,
                            ),
                  },
                ),
                if (widget.offerInquiry != null)
                  _MakeOfferBar(
                    inquiry: widget.offerInquiry!,
                    onPressed: () => _openMakeOffer(widget.offerInquiry!),
                  ),
                ChatOfferPanel(
                  state: offers,
                  currentUserId: widget.currentUserId,
                  onAccept: _acceptOffer,
                  onDecline: _declineOffer,
                  onWithdraw: _withdrawOffer,
                  onRetry: _offers.load,
                ),
                ChatInputBar(onSend: _onSend, isSending: state.isSending),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.messages, required this.currentUserId});

  final List<Message> messages;
  final int currentUserId;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
        vertical: AppSpacing.sm,
      ),
      itemCount: messages.length,
      itemBuilder: (BuildContext context, int index) {
        final Message message = messages[index];
        return MessageBubble(
          message: message,
          isMine: message.isSentBy(currentUserId),
          isPlaceholder: message.id < 0,
        );
      },
    );
  }
}

class _SmallAvatar extends StatelessWidget {
  const _SmallAvatar({required this.user});

  final ChatUser user;

  @override
  Widget build(BuildContext context) {
    final String? url = user.avatarUrl;
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: 16,
        child: Text(user.initial, style: const TextStyle(fontSize: 12)),
      );
    }
    return CircleAvatar(radius: 16, backgroundImage: NetworkImage(url));
  }
}

class _EmptyThread extends StatelessWidget {
  const _EmptyThread();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Say hello', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Start the conversation below.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: AppSpacing.sm),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

/// The larger avatar in the profile sheet: the real photo when the account has
/// one, the same initials fallback the chat list uses otherwise.
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.user});

  final ChatUser user;

  @override
  Widget build(BuildContext context) {
    final String? url = user.avatarUrl;
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: 32,
        child: Text(user.initial, style: const TextStyle(fontSize: 24)),
      );
    }
    return CircleAvatar(radius: 32, backgroundImage: NetworkImage(url));
  }
}

/// The seller's in-chat action for the inquiry the server marked eligible.
///
/// It sits above the existing offer panel and above the composer: the seller
/// answers the inquiry without leaving the conversation. The inquiry id is
/// never inferred here — it comes from `ConversationResource.eligible_inquiry`,
/// which already excludes inquiries with a pending offer and inquiries where
/// the caller is the buyer.
class _MakeOfferBar extends StatelessWidget {
  const _MakeOfferBar({required this.inquiry, required this.onPressed});

  final ConversationEligibleInquiry inquiry;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? listing = inquiry.listingTitle;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.xs,
        AppSpacing.screenGutter,
        AppSpacing.xs,
      ),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            listing == null ? 'Answer this inquiry' : 'Inquiry · $listing',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: const Icon(Icons.local_offer_outlined, size: 18),
            label: const Text('Make an Offer'),
          ),
        ],
      ),
    );
  }
}
