import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/conversation.dart';
import '../../../models/inquiry_list_item.dart';
import '../../../models/message.dart';
import '../../../models/transaction.dart';
import '../../../repositories/inquiry_repository.dart';
import '../../../repositories/transaction_repository.dart';
import '../../auth/state/auth_scope.dart';
import '../../inquiries/state/active_inquiries_controller.dart';
import '../../inquiries/state/inquiry_scope.dart';
import '../../transactions/state/transaction_scope.dart';
import '../../transactions/state/transactions_controller.dart';
import '../../transactions/state/transactions_state.dart';
import '../../transactions/views/transaction_detail_screen.dart';
import '../../transactions/widgets/transaction_card.dart';
import '../state/conversations_controller.dart';
import '../state/messaging_scope.dart';
import '../state/messaging_state.dart';
import '../widgets/conversation_tile.dart';
import 'chat_screen.dart';

/// The caller's inbox — every thread they are part of, scoped to the active
/// account mode.
///
/// Reads the session-scoped [ConversationsController] from [MessagingScope].
/// Opening a chat pushes [ChatScreen], which is where the messages actually
/// load; this screen only knows the summary each conversation carries.
///
/// Search and the category filter are **local view filters** over the one
/// response `GET /conversations` returns (Messages design §3.2–§3.3): the API
/// offers no conversation search, and an inbox is small by construction. The
/// "Inquiries" and "Transactions" filters read the pair-level booleans the
/// server computes (`has_inquiry`, `has_transaction`), so neither guesses from
/// the listing context of the newest message.
///
/// [sellerMode] is the existing Account Mode, passed by the shell that mounts
/// this screen. Buyer Mode shows threads where the caller acts as a buyer;
/// Seller Mode shows seller-side threads; a pair the caller trades with in both
/// directions appears in both, and an unclassifiable thread is never hidden.
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({this.sellerMode = false, super.key});

  /// Which side of the pair the inbox should show.
  final bool sellerMode;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  late final ConversationsController _controller;

  /// Tab repositories are resolved lazily, when a tab is first opened. The
  /// shell builds this screen inside an IndexedStack, so resolving a scope it
  /// does not need yet would couple every shell test to every feature scope.
  InquiryRepository? _inquiryRepository;
  TransactionRepository? _transactionRepository;

  ActiveInquiriesController? _inquiries;
  TransactionsController? _transactions;

  /// The text field's own buffer. The *query* lives in controller state (so
  /// it survives tab switches); this controller only owns the caret and the
  /// bytes on screen.
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    // `readOf` — the dependency is registered from the ListenableBuilder.
    _controller = MessagingScope.readOf(context);
    _controller.load();
  }

  @override
  void dispose() {
    _inquiries?.dispose();
    _transactions?.dispose();
    _search.dispose();
    super.dispose();
  }

  /// The side the active Account Mode asks the tab APIs for.
  String get _role => widget.sellerMode ? 'seller' : 'buyer';

  /// Switches the chip and lazily loads the tab's own records.
  ///
  /// "All" keeps using the single `/conversations` response; the other two
  /// tabs read their own server lists the first time they are opened, so the
  /// inbox never pays for data the user did not ask for.
  void _selectFilter(InboxFilter filter) {
    // Creating a tab controller changes the list the ListenableBuilder merges,
    // so the screen itself must rebuild. Without this, the builder keeps the
    // merge captured before the controller existed and never hears the tab's
    // success/failure notification — the spinner that never ends.
    setState(() {
      _controller.setFilter(filter);

      if (filter == InboxFilter.inquiries) {
        _inquiryRepository ??= context
            .getInheritedWidgetOfExactType<InquiryScope>()
            ?.repository;
        final InquiryRepository? repository = _inquiryRepository;
        if (repository != null) {
          _inquiries ??= ActiveInquiriesController(repository, role: _role);
        }
      }

      if (filter == InboxFilter.transactions) {
        _transactionRepository ??= context
            .getInheritedWidgetOfExactType<TransactionScope>()
            ?.repository;
        final TransactionRepository? repository = _transactionRepository;
        if (repository != null) {
          _transactions ??= TransactionsController(
            repository,
            null,
            role: widget.sellerMode
                ? TransactionRole.seller
                : TransactionRole.buyer,
          );
        }
      }
    });

    // Load once per tab. Re-selecting a tab keeps the loaded/error state and
    // never fires a second request; pull-to-refresh and Retry own refreshes.
    final ActiveInquiriesController? inquiries = _inquiries;
    if (filter == InboxFilter.inquiries &&
        inquiries?.state.status == ActiveInquiriesStatus.initial) {
      inquiries!.load();
    }

    final TransactionsController? transactions = _transactions;
    if (filter == InboxFilter.transactions &&
        transactions?.state.status == TransactionsStatus.initial) {
      transactions!.loadInitial();
    }
  }

  void _clearSearch() {
    _search.clear();
    _controller.setSearch('');
  }

  Future<void> _openChat(Conversation conversation, int currentUserId) async {
    // Optimistic: mark read before the navigation completes so the badge
    // clears immediately.
    unawaited(_controller.markRead(conversation.counterpart.id));

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ChatScreen(
          counterpart: conversation.counterpart,
          currentUserId: currentUserId,
          // The seller-side action only exists in Seller Mode; the server has
          // already decided which inquiry is eligible, so the chat never
          // guesses one.
          offerInquiry: widget.sellerMode ? conversation.eligibleInquiry : null,
          counterpartRole: conversation.counterpartRole,
        ),
      ),
    );
    // On return, re-fetch so a message sent in the chat screen updates the
    // last-message preview without a manual pull.
    await _controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    // Read the caller's user id here, in `build`, where `AuthScope.of` is
    // safe. Passed into `ChatScreen` because that screen's `initState`
    // cannot register an inherited-widget dependency.
    final int currentUserId = AuthScope.of(context).state.user?.id ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: ListenableBuilder(
        listenable: Listenable.merge(
          <Listenable?>[
            _controller,
            _inquiries,
            _transactions,
          ].whereType<Listenable>().toList(growable: false),
        ),
        builder: (BuildContext context, Widget? child) {
          final ConversationsState state = _controller.state;

          if (state.isInitialLoad) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.status == ConversationsStatus.failed) {
            return _ErrorState(
              message: state.errorMessage ?? 'Something went wrong.',
              onRetry: _controller.load,
            );
          }

          return Column(
            children: <Widget>[
              _SearchField(
                controller: _search,
                query: state.query,
                onChanged: _controller.setSearch,
                onClear: _clearSearch,
              ),
              _FilterRow(filter: state.filter, onSelected: _selectFilter),
              Expanded(
                child: switch (state.filter) {
                  InboxFilter.all => _conversationArea(state, currentUserId),
                  InboxFilter.inquiries => _inquiryArea(state.query),
                  InboxFilter.transactions => _transactionArea(state.query),
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// The inquiry tab: individual active inquiries, each opening its chat.
  Widget _inquiryArea(String query) {
    final ActiveInquiriesController? controller = _inquiries;
    if (controller == null) {
      return const _TabEmpty(
        icon: Icons.receipt_long_outlined,
        title: 'Inquiries unavailable',
        body: 'Reload Messages to try again.',
      );
    }

    final ActiveInquiriesState tab = controller.state;
    if (tab.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tab.status == ActiveInquiriesStatus.failed) {
      return _ErrorState(
        message: tab.errorMessage ?? 'Could not load inquiries.',
        onRetry: controller.load,
      );
    }

    final String needle = query.trim().toLowerCase();
    final List<InquiryListItem> items = tab.items
        .where((InquiryListItem item) {
          if (needle.isEmpty) {
            return true;
          }
          return (item.listing?.title.toLowerCase().contains(needle) ??
                  false) ||
              (item.counterpart?.name.toLowerCase().contains(needle) ??
                  false) ||
              item.message.toLowerCase().contains(needle);
        })
        .toList(growable: false);

    if (items.isEmpty) {
      return const _TabEmpty(
        icon: Icons.receipt_long_outlined,
        title: 'No active inquiries',
        body: 'Inquiries waiting for a decision appear here.',
      );
    }

    final int currentUserId = AuthScope.of(context).state.user?.id ?? 0;

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (BuildContext context, int index) =>
            const Divider(height: 1, indent: 72),
        itemBuilder: (BuildContext context, int index) {
          final InquiryListItem item = items[index];
          return _InquiryTabTile(
            inquiry: item,
            onTap: () => _openInquiryChat(item, currentUserId),
          );
        },
      ),
    );
  }

  /// The transactions tab: accepted agreements, read-only, with the two
  /// navigation actions the Messages screen owns (detail and chat). Managing a
  /// transaction still happens in the bottom Transactions module.
  Widget _transactionArea(String query) {
    final TransactionsController? controller = _transactions;
    if (controller == null) {
      return const _TabEmpty(
        icon: Icons.swap_horiz_outlined,
        title: 'Transactions unavailable',
        body: 'Reload Messages to try again.',
      );
    }

    final TransactionsState tab = controller.state;
    if (tab.status == TransactionsStatus.loading ||
        tab.status == TransactionsStatus.initial) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tab.status == TransactionsStatus.failed) {
      return _ErrorState(
        message: tab.errorMessage ?? 'Could not load transactions.',
        onRetry: controller.loadInitial,
      );
    }

    final String needle = query.trim().toLowerCase();
    final List<Transaction> items = tab.transactions
        .where((Transaction transaction) {
          if (needle.isEmpty) {
            return true;
          }
          final String listing =
              '${transaction.listing.livestockType} ${transaction.listing.breed}'
                  .toLowerCase();
          return listing.contains(needle) ||
              transaction.counterparty.name.toLowerCase().contains(needle);
        })
        .toList(growable: false);

    if (items.isEmpty) {
      return const _TabEmpty(
        icon: Icons.swap_horiz_outlined,
        title: 'No transactions yet',
        body: 'Accepted offers appear here as transaction records.',
      );
    }

    final int currentUserId = AuthScope.of(context).state.user?.id ?? 0;

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (BuildContext context, int index) =>
            const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) {
          final Transaction transaction = items[index];
          return Column(
            children: <Widget>[
              TransactionCard(
                transaction: transaction,
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        TransactionDetailScreen(transactionId: transaction.id),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenGutter,
                  0,
                  AppSpacing.screenGutter,
                  AppSpacing.xs,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TextButton.icon(
                      onPressed: () =>
                          _openTransactionChat(transaction, currentUserId),
                      icon: const Icon(Icons.chat_bubble_outline, size: 16),
                      label: const Text('Open chat'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openInquiryChat(InquiryListItem item, int currentUserId) async {
    final InquiryCounterpart? counterpart = item.counterpart;
    if (counterpart == null) {
      return;
    }

    final ConversationEligibleInquiry? offer =
        widget.sellerMode &&
            !item.isBuyer &&
            item.canMakeOffer &&
            item.listing != null
        ? ConversationEligibleInquiry(
            id: item.id,
            listingId: item.listing!.id,
            listingTitle: item.listing!.title,
            askingPrice: item.listing!.askingPrice,
            photoUrl: item.listing!.photoUrl,
            paymentMethod: item.paymentMethod,
            collectionMethod: item.collectionMethod,
            preferredSchedule: item.preferredSchedule,
          )
        : null;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ChatScreen(
          counterpart: ChatUser(
            id: counterpart.id,
            name: counterpart.name,
            avatarUrl: null,
          ),
          currentUserId: currentUserId,
          counterpartRole: item.counterpartRole,
          offerInquiry: offer,
        ),
      ),
    );
    await _controller.refresh();
  }

  Future<void> _openTransactionChat(
    Transaction transaction,
    int currentUserId,
  ) async {
    final bool isBuyer = transaction.role == TransactionRole.buyer;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ChatScreen(
          counterpart: ChatUser(
            id: transaction.counterparty.id,
            name: transaction.counterparty.name,
            avatarUrl: null,
          ),
          currentUserId: currentUserId,
          counterpartRole: isBuyer ? 'Seller' : 'Buyer',
        ),
      ),
    );
    await _controller.refresh();
  }

  /// The list, the empty inbox, or the no-matches state — the three bodies a
  /// loaded inbox can show, each pull-to-refresh capable.
  Widget _conversationArea(ConversationsState state, int currentUserId) {
    if (state.conversations.isEmpty) {
      return const _EmptyState();
    }

    final List<Conversation> visible = state.visibleConversations(
      sellerMode: widget.sellerMode,
    );

    if (visible.isEmpty) {
      return const _NoMatchesState();
    }

    return RefreshIndicator(
      onRefresh: _controller.refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: visible.length,
        separatorBuilder: (BuildContext context, int index) =>
            const Divider(height: 1, indent: 72),
        itemBuilder: (BuildContext context, int index) {
          final Conversation conversation = visible[index];
          return ConversationTile(
            conversation: conversation,
            onTap: () => _openChat(conversation, currentUserId),
          );
        },
      ),
    );
  }
}

// Local helper so the file does not need to import dart:async just for this.
void unawaited(Future<void> future) {
  future.ignore();
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.5,
          child: Center(
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
                  Text('No messages yet', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Start a conversation from any listing.',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The rounded local-search field. Filtering happens in
/// [ConversationsState.visibleConversations] — no request is made.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        AppSpacing.xs,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search conversations...',
          prefixIcon: const Icon(Icons.search),
          // Present only while there is something to clear; a suffix icon
          // with an empty handler would still be a tappable dead control.
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear search',
                  onPressed: onClear,
                ),
        ),
      ),
    );
  }
}

/// The All / Inquiries / Transactions chip row.
///
/// All three are selectable local filters over the server's pair-level
/// `has_inquiry` / `has_transaction` facts. Notifications is not a conversation
/// category and is no longer offered here: it stays on Home's bell, which opens
/// the existing notifications destination.
class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.filter, required this.onSelected});

  final InboxFilter filter;
  final ValueChanged<InboxFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenGutter),
      child: Row(
        children: <Widget>[
          _FilterChip(
            label: 'All',
            selected: filter == InboxFilter.all,
            onTap: () => onSelected(InboxFilter.all),
          ),
          const SizedBox(width: AppSpacing.xs),
          _FilterChip(
            label: 'Inquiries',
            selected: filter == InboxFilter.inquiries,
            onTap: () => onSelected(InboxFilter.inquiries),
          ),
          const SizedBox(width: AppSpacing.xs),
          _FilterChip(
            label: 'Transactions',
            selected: filter == InboxFilter.transactions,
            onTap: () => onSelected(InboxFilter.transactions),
          ),
        ],
      ),
    );
  }
}

/// One filter chip. Selected = solid primary green with white text; unselected
/// = surface with a border; disabled = the same, dimmed and inert.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;

  /// `null` disables the chip.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final BorderRadius radius = BorderRadius.circular(AppRadius.xl);

    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Material(
        color: selected ? AppColors.primary : AppColors.surface,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Conversations exist, but the current search and/or filter matches none.
class _NoMatchesState extends StatelessWidget {
  const _NoMatchesState();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.35,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.search_off,
                    size: 48,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'No matching conversations',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Try a different search or filter.',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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

/// One active inquiry in the Messages "Inquiries" tab.
class _InquiryTabTile extends StatelessWidget {
  const _InquiryTabTile({required this.inquiry, required this.onTap});

  final InquiryListItem inquiry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? price = inquiry.listing?.askingPrice == null
        ? null
        : AppFormatters.formatMoney(inquiry.listing!.askingPrice!) ??
              inquiry.listing!.askingPrice;
    final String? photo = inquiry.listing?.photoUrl;
    final String? status = _statusLabel(inquiry);
    final bool decision = inquiry.needsBuyerDecision;

    return Material(
      color: decision ? AppColors.primarySurface : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenGutter,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Thumb(url: photo),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            inquiry.counterpart?.name ?? 'Unknown user',
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (status != null)
                          _StatusBadge(label: status, emphasised: decision),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        inquiry.listing?.title ?? 'Listing no longer available',
                        ?price,
                      ].join(' · '),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      inquiry.message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      inquiry.isBuyer
                          ? 'You are the buyer'
                          : 'You are the seller',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String? _statusLabel(InquiryListItem inquiry) {
    final InquiryOfferSummary? offer = inquiry.latestOffer;
    if (offer == null) {
      return 'No offer yet';
    }
    return switch (offer.status) {
      'pending' => inquiry.isBuyer ? 'Needs your decision' : 'Offer pending',
      'declined' => 'Offer declined',
      'withdrawn' => 'Offer withdrawn',
      _ => 'Offer ${offer.status}',
    };
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.emphasised});

  final String label;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(left: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: emphasised ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: emphasised ? AppColors.primary : AppColors.border,
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: emphasised ? Colors.white : AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final String? source = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(
        width: 56,
        height: 56,
        child: source == null || source.isEmpty
            ? Container(
                color: AppColors.primarySurface,
                child: const Icon(
                  Icons.pets_outlined,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
              )
            : Image.network(
                source,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: AppColors.primarySurface,
                  child: const Icon(
                    Icons.pets_outlined,
                    color: AppColors.textSecondary,
                    size: 22,
                  ),
                ),
              ),
      ),
    );
  }
}

class _TabEmpty extends StatelessWidget {
  const _TabEmpty({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.35,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 48, color: AppColors.textSecondary),
                  const SizedBox(height: AppSpacing.sm),
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
