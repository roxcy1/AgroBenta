import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/notification_preferences.dart';
import '../../notifications/state/notifications_scope.dart';
import '../state/notification_settings_controller.dart';

/// Profile → Notification Settings: one push switch per notification type.
///
/// The switches are saved on the server, so they apply to every phone the
/// user signs in on. A switched-off type is still listed in Notifications;
/// only its phone push stops.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late final NotificationSettingsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = NotificationSettingsController(
      NotificationsScope.repositoryOf(context),
    )..addListener(_showSaveError);
    _controller.load();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_showSaveError)
      ..dispose();
    super.dispose();
  }

  void _showSaveError() {
    final String? message = _controller.saveError;
    if (message == null || !mounted) {
      return;
    }
    _controller.clearSaveError();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification Settings')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (BuildContext context, Widget? child) {
          switch (_controller.status) {
            case NotificationSettingsStatus.loading:
              return const Center(child: CircularProgressIndicator());
            case NotificationSettingsStatus.failed:
              return _LoadFailed(
                message: _controller.loadError,
                onRetry: _controller.load,
              );
            case NotificationSettingsStatus.ready:
              return _Switches(controller: _controller);
          }
        },
      ),
    );
  }
}

class _Switches extends StatelessWidget {
  const _Switches({required this.controller});

  final NotificationSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NotificationPreferences preferences = controller.preferences!;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: <Widget>[
        Text('Phone notifications', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Choose which updates appear on your phone. Turned-off updates '
          'still show in Notifications in the app.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              for (final NotificationCategory category
                  in NotificationCategory.values) ...<Widget>[
                if (category != NotificationCategory.values.first)
                  const Divider(height: 1),
                SwitchListTile(
                  title: Text(category.label),
                  subtitle: Text(
                    category.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  value: preferences.isEnabled(category),
                  onChanged: controller.isSaving(category)
                      ? null
                      : (bool enabled) =>
                            controller.setEnabled(category, enabled: enabled),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message ?? 'Could not load your notification settings.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
