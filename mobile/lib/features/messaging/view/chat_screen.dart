import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/message.dart';
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
    super.key,
  });

  /// The other user in the thread.
  final ChatUser counterpart;

  /// The caller's user id — from the authenticated session, passed by the
  /// caller because [AuthScope] cannot be reached from `initState`.
  final int currentUserId;

  /// The listing this thread is about, if any.
  final int? listingId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatController _controller;

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
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _onSend(String body) => _controller.send(body);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[
            _SmallAvatar(user: widget.counterpart),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                widget.counterpart.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? child) {
            final ChatState state = _controller.state;

            // A send error is shown as a snackbar, once.
            final String? sendError = state.sendErrorMessage;
            if (sendError != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(sendError)),
                );
                _controller.clearSendError();
              });
            }

            return Column(
              children: <Widget>[
                Expanded(
                  child: switch (state.status) {
                    ChatStatus.initial || ChatStatus.loading =>
                      const Center(child: CircularProgressIndicator()),
                    ChatStatus.failed => _ErrorState(
                        message: state.errorMessage ?? 'Something went wrong.',
                        onRetry: _controller.load,
                      ),
                    _ => state.messages.isEmpty
                        ? const _EmptyThread()
                        : _MessageList(
                            messages: state.messages,
                            currentUserId: widget.currentUserId,
                          ),
                  },
                ),
                ChatInputBar(
                  onSend: _onSend,
                  isSending: state.isSending,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.currentUserId,
  });

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
        child: Text(
          user.initial,
          style: const TextStyle(fontSize: 12),
        ),
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
            Text(
              'Say hello',
              style: theme.textTheme.titleMedium,
            ),
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