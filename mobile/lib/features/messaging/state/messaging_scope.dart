import 'package:flutter/widgets.dart';

import '../../../repositories/messaging_repository.dart';
import 'conversations_controller.dart';

/// Makes the shared [MessagingRepository] and the session-scoped
/// [ConversationsController] available to the messaging screens.
///
/// Installed above `MaterialApp` in `main.dart`, like every other feature
/// scope: the chat screen is a pushed route and a scope inside `home` would
/// be invisible to it.
///
/// ## Why the controller lives here and not on the screen
///
/// The inbox controller is session-scoped on purpose. The buyer shell needs
/// to read its `hasUnread` to show a badge on the Messages tab, and that
/// badge must reflect the same state the Conversations screen shows. If the
/// controller were per-screen, the shell would need its own copy and the two
/// could disagree.
///
/// The [ChatController] is *not* here — it is per-screen, created and
/// disposed by the chat screen itself.
class MessagingScope extends InheritedWidget {
  const MessagingScope({
    required this.repository,
    required this.conversationsController,
    required super.child,
    super.key,
  });

  final MessagingRepository repository;
  final ConversationsController conversationsController;

  /// The repository, for a chat screen creating its own controller.
  static MessagingRepository repositoryOf(BuildContext context) {
    final MessagingScope? scope =
        context.dependOnInheritedWidgetOfExactType<MessagingScope>();
    assert(scope != null, 'No MessagingScope found in context.');
    return scope!.repository;
  }

  /// The repository, without registering a dependency. For `initState`.
  static MessagingRepository readRepositoryOf(BuildContext context) {
    final MessagingScope? scope =
        context.getInheritedWidgetOfExactType<MessagingScope>();
    assert(scope != null, 'No MessagingScope found in context.');
    return scope!.repository;
  }

  /// The inbox controller, registering [context] as a dependency.
  static ConversationsController of(BuildContext context) {
    final MessagingScope? scope =
        context.dependOnInheritedWidgetOfExactType<MessagingScope>();
    assert(scope != null, 'No MessagingScope found in context.');
    return scope!.conversationsController;
  }

  /// The inbox controller, without registering a dependency. For `initState`.
  static ConversationsController readOf(BuildContext context) {
    final MessagingScope? scope =
        context.getInheritedWidgetOfExactType<MessagingScope>();
    assert(scope != null, 'No MessagingScope found in context.');
    return scope!.conversationsController;
  }

  @override
  bool updateShouldNotify(MessagingScope oldWidget) =>
      repository != oldWidget.repository ||
      conversationsController != oldWidget.conversationsController;
}