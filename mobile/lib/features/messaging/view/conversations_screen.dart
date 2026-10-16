import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/conversation.dart';
import '../../auth/state/auth_scope.dart';
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
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  late final ConversationsController _controller;

  @override
  void initState() {
    super.initState();
    // `readOf` — the dependency is registered from the ListenableBuilder.
    _controller = MessagingScope.readOf(context);
    _controller.load();
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

          if (state.conversations.isEmpty) {
            return const _EmptyState();
          }

          return RefreshIndicator(
            onRefresh: _controller.refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: state.conversations.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const Divider(height: 1, indent: 72),
              itemBuilder: (BuildContext context, int index) {
                final Conversation conversation = state.conversations[index];
                return ConversationTile(
                  conversation: conversation,
                  onTap: () => _openChat(conversation, currentUserId),
                );
              },
            ),
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
                  Text(
                    'No messages yet',
                    style: theme.textTheme.titleMedium,
                  ),
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