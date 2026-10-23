import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/conversation.dart';
import '../../auth/state/auth_scope.dart';
import '../../notifications/view/notifications_screen.dart';
import '../state/conversations_controller.dart';
import '../state/messaging_scope.dart';
import '../state/messaging_state.dart';
import '../widgets/conversation_tile.dart';
import 'chat_screen.dart';

/// The caller's inbox — every thread they are part of.
///
/// Reads the session-scoped [ConversationsController] from [MessagingScope].
/// Opening a chat pushes [ChatScreen], which is where the messages actually
/// load; this screen only knows the summary each conversation carries.
///
/// Search and the category filter are **local view filters** over the one
/// response `GET /conversations` returns (Messages design §3.2–§3.3): the API
/// offers no conversation search, and an inbox is small by construction. The
/// "Inquiries" filter selects listing-scoped threads (`listing_id != null`).
/// "Transactions" renders disabled because the API links no message to a
/// transaction (GAP-11). "Notifications" is not a conversation category at all
/// — it opens the separate, already-built notifications destination, as the
/// design prescribes.
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  late final ConversationsController _controller;

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
    _search.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _search.clear();
    _controller.setSearch('');
  }

  /// Notification threads do not exist: notifications have their own inbox and
  /// their own destination (Home's bell). The chip leads there instead of
  /// pretending they are conversations (Messages design §3.3).
  void _openNotifications() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const NotificationsScreen(),
      ),
    );
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
          listingId: conversation.listingId,
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
        listenable: _controller,
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
              _FilterRow(
                filter: state.filter,
                onSelected: _controller.setFilter,
                onNotifications: _openNotifications,
              ),
              Expanded(child: _conversationArea(state, currentUserId)),
            ],
          );
        },
      ),
    );
  }

  /// The list, the empty inbox, or the no-matches state — the three bodies a
  /// loaded inbox can show, each pull-to-refresh capable.
  Widget _conversationArea(ConversationsState state, int currentUserId) {
    if (state.conversations.isEmpty) {
      return const _EmptyState();
    }
    if (state.visibleConversations.isEmpty) {
      return const _NoMatchesState();
    }

    return RefreshIndicator(
      onRefresh: _controller.refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.visibleConversations.length,
        separatorBuilder: (BuildContext context, int index) =>
            const Divider(height: 1, indent: 72),
        itemBuilder: (BuildContext context, int index) {
          final Conversation conversation = state.visibleConversations[index];
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

/// The All / Inquiries / Transactions / Notifications chip row.
///
/// Only [InboxFilter.all] and [InboxFilter.inquiries] are selectable — they
/// are the only categories the conversation data can answer. "Transactions"
/// is rendered disabled (GAP-11: no transaction-message link; Messages design
/// §3.3: report the gap, never populate a filter with fake data).
/// "Notifications" is an enabled **shortcut** to the existing notifications
/// destination, not a filter; its trailing icon says so.
class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.filter,
    required this.onSelected,
    required this.onNotifications,
  });

  final InboxFilter filter;
  final ValueChanged<InboxFilter> onSelected;
  final VoidCallback onNotifications;

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
          // Not supported: the API links no message or conversation to a
          // transaction (GAP-11). Disabled, not hidden — the category is
          // part of the product, its data is not there yet.
          const _FilterChip(
            label: 'Transactions',
            selected: false,
            onTap: null,
          ),
          const SizedBox(width: AppSpacing.xs),
          // Not a thread category. Opens the notifications inbox.
          _FilterChip(
            label: 'Notifications',
            selected: false,
            onTap: onNotifications,
            trailing: const Icon(
              Icons.open_in_new,
              size: 14,
              color: AppColors.textSecondary,
            ),
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
    this.trailing,
  });

  final String label;
  final bool selected;

  /// `null` disables the chip.
  final VoidCallback? onTap;

  /// An optional glyph after the label — used by the Notifications chip to
  /// signal that it navigates instead of filtering.
  final Widget? trailing;

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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected ? Colors.white : AppColors.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                if (trailing != null) ...<Widget>[
                  const SizedBox(width: AppSpacing.xxs),
                  trailing!,
                ],
              ],
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
