import 'package:flutter/material.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/app_notification.dart';
import '../state/notifications_controller.dart';
import '../state/notifications_scope.dart';
import '../state/notifications_state.dart';
import '../widgets/notification_filter_bar.dart';
import '../widgets/notification_tile.dart';

/// The caller's notification inbox.
///
/// Pushed from the bell icon on the Home AppBar. Reads the session-scoped
/// [NotificationsController] so the bell badge and this screen share state.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final NotificationsController _controller;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = NotificationsScope.readOf(context);
    // Ensure the first page is loaded even if the badge-only call has been
    // the only network activity so far.
    _controller.load();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final ScrollPosition position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      _controller.loadMore();
    }
  }

  /// Taps a notification: mark read optimistically, then navigate to the
  /// action's target if any. The action targets are placeholders in this
  /// phase — the notifications screen has no deep-link wiring yet, so a tap
  /// simply clears the unread state and stays put.
  Future<void> _onTap(AppNotification notification) async {
    unawaited(_controller.markRead(notification.id));
    // TODO(deep-link): route to the target screen once deep-linking lands.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: <Widget>[
          ListenableBuilder(
            listenable: _controller,
            builder: (BuildContext context, Widget? child) {
              final bool hasUnread = _controller.state.unreadCount > 0;
              return TextButton(
                onPressed: hasUnread ? _controller.markAllRead : null,
                child: const Text('Mark all read'),
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (BuildContext context, Widget? child) {
          final NotificationsState state = _controller.state;

          return Column(
            children: <Widget>[
              NotificationFilterBar(
                filters: NotificationEndpoints.filterTypes,
                selected: state.activeFilter,
                onSelected: _controller.applyFilter,
              ),
              if (state.loadMoreErrorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenGutter,
                  ),
                  child: Text(
                    state.loadMoreErrorMessage!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Expanded(
                child: switch (state.status) {
                  NotificationsStatus.initial ||
                  NotificationsStatus.loading => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  NotificationsStatus.failed => _ErrorState(
                    message: state.errorMessage ?? 'Something went wrong.',
                    onRetry: _controller.refresh,
                  ),
                  _ => state.isEmpty
                      ? const _EmptyState()
                      : RefreshIndicator(
                          onRefresh: _controller.refresh,
                          child: _NotificationList(
                            state: state,
                            scrollController: _scrollController,
                            onTap: _onTap,
                          ),
                        ),
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

// Local helper so the file does not import dart:async.
void unawaited(Future<void> future) {
  future.ignore();
}

class _NotificationList extends StatelessWidget {
  const _NotificationList({
    required this.state,
    required this.scrollController,
    required this.onTap,
  });

  final NotificationsState state;
  final ScrollController scrollController;
  final ValueChanged<AppNotification> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: state.notifications.length + 1,
      separatorBuilder: (BuildContext context, int index) =>
          const Divider(height: 1, indent: 68),
      itemBuilder: (BuildContext context, int index) {
        if (index == state.notifications.length) {
          return _ListFooter(state: state);
        }
        final AppNotification notification = state.notifications[index];
        return NotificationTile(
          notification: notification,
          onTap: () => onTap(notification),
        );
      },
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.state});

  final NotificationsState state;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return const SizedBox(height: AppSpacing.md);
  }
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
          height: MediaQuery.sizeOf(context).height * 0.45,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.notifications_none_outlined,
                    size: 48,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'No notifications',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Updates about your listings, inquiries, and account will appear here.',
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