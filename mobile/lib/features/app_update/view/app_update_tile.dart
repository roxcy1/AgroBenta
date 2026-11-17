import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/app_release.dart';
import '../state/app_update_controller.dart';
import '../state/app_update_scope.dart';

/// The Profile screen's "App Update" row.
///
/// Shows the installed version, checks the server for a newer build when it
/// appears, and on tap either checks again or offers the newer build. The
/// update itself is a download in the phone's browser; Android's installer
/// replaces the app and keeps the user signed in.
class AppUpdateTile extends StatefulWidget {
  const AppUpdateTile({required this.leading, super.key});

  /// The row's icon, styled by the screen that hosts it.
  final Widget leading;

  @override
  State<AppUpdateTile> createState() => _AppUpdateTileState();
}

class _AppUpdateTileState extends State<AppUpdateTile> {
  late final AppUpdateController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppUpdateController(AppUpdateScope.readOf(context));
    _controller.check();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_controller.status != AppUpdateStatus.updateAvailable) {
      await _controller.check();
      if (!mounted) return;
      if (_controller.status == AppUpdateStatus.upToDate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You have the latest version.')),
        );
      }
      return;
    }

    final AppRelease release = _controller.latest!;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => _UpdateDialog(release: release),
    );
    if (confirmed != true || !mounted) return;

    final bool opened = await _controller.openDownload();
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not open the download. Download the update from the '
          'AgroBenta website instead.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? child) {
        final String installed = _controller.installed == null
            ? ''
            : 'Version ${_controller.installed!.name} · ';
        final bool available =
            _controller.status == AppUpdateStatus.updateAvailable;

        final String subtitle = switch (_controller.status) {
          AppUpdateStatus.idle ||
          AppUpdateStatus.checking => '${installed}Checking for updates…',
          AppUpdateStatus.upToDate => '${installed}Up to date',
          AppUpdateStatus.updateAvailable =>
            'Version ${_controller.latest!.versionName} is available',
          AppUpdateStatus.failed =>
            '${installed}Could not check. Tap to retry.',
        };

        final Widget trailing = switch (_controller.status) {
          AppUpdateStatus.checking => const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          AppUpdateStatus.updateAvailable => _UpdateBadge(
            busy: _controller.isOpeningDownload,
          ),
          _ => const Icon(
            Icons.refresh,
            size: 20,
            color: AppColors.textSecondary,
          ),
        };

        return ListTile(
          leading: widget.leading,
          title: Text('App Update', style: theme.textTheme.titleSmall),
          subtitle: Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: available ? AppColors.primary : AppColors.textSecondary,
              fontWeight: available ? FontWeight.w600 : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: trailing,
          onTap:
              _controller.status == AppUpdateStatus.checking ||
                  _controller.isOpeningDownload
              ? null
              : _onTap,
        );
      },
    );
  }
}

class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Update',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.release});

  final AppRelease release;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String size = (release.sizeBytes / (1024 * 1024)).toStringAsFixed(1);
    final String? notes = release.notes;

    return AlertDialog(
      title: Text('Update to version ${release.versionName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (notes != null) ...<Widget>[
            Text(notes, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
          ],
          Text(
            'The update ($size MB) downloads in your browser. When it finishes, '
            'open the file and tap Update. If your phone asks, allow your '
            'browser to install apps. You stay signed in.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Download update'),
        ),
      ],
    );
  }
}
