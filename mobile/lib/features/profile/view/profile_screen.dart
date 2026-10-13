import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/user.dart';
import '../state/profile_controller.dart';
import '../state/profile_scope.dart';
import '../state/profile_state.dart';
import 'change_password_screen.dart';
import 'edit_profile_screen.dart';

/// The caller's own profile.
///
/// Reached from the buyer shell's bottom navigation. Read-only until the user
/// taps "Edit profile", which pushes the form. A "Change password" action is
/// offered separately because the password is not part of the profile resource
/// and has its own endpoint.
///
/// Reads the controller once in `initState` and rebuilds from
/// [ListenableBuilder], so a keystroke elsewhere does not rebuild the whole
/// tree — the same pattern `SellerListingsScreen` uses.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileController _controller;

  @override
  void initState() {
    super.initState();
    // `readOf`, not `of`: a dependency cannot be registered from `initState`,
    // and the whole screen already listens to the controller directly.
    _controller = ProfileScope.readOf(context);
    // Idempotent while in flight; a rebuild that re-enters this is a no-op.
    _controller.load();
  }

  Future<void> _openEdit() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => const EditProfileScreen(),
        fullscreenDialog: true,
      ),
    );
    // Nothing to do on return — the controller already holds the updated
    // profile and the ListenableBuilder rebuilds. The result value is
    // intentionally ignored: it exists so a future change can react to a save
    // without changing the edit screen's contract.
  }

  Future<void> _openChangePassword() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const ChangePasswordScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (BuildContext context, Widget? child) {
          final ProfileState state = _controller.state;

          // A success message is one-shot: show it, then clear it so the next
          // rebuild does not show it again. Deferred to after the frame so a
          // `setState` during build is avoided.
          final String? success = state.successMessage;
          if (success != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(success)),
              );
              _controller.consumeSuccess();
            });
          }

          return switch (state.status) {
            ProfileUiStatus.initial ||
            ProfileUiStatus.loading => const Center(
              child: CircularProgressIndicator(),
            ),
            ProfileUiStatus.failed => _ErrorState(
              message: state.errorMessage ?? 'Something went wrong.',
              onRetry: _controller.load,
            ),
            _ => _ProfileBody(
              user: state.user!,
              onEdit: _openEdit,
              onChangePassword: _openChangePassword,
            ),
          };
        },
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({
    required this.user,
    required this.onEdit,
    required this.onChangePassword,
  });

  final User user;
  final VoidCallback onEdit;
  final VoidCallback onChangePassword;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Avatar(name: user.name, url: user.avatarUrl),
                const SizedBox(height: AppSpacing.md),
                Text(
                  user.name,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  user.email,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (user.isSeller) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  const Center(child: _VerifiedBadge()),
                ],
                const SizedBox(height: AppSpacing.lg),
                _InfoSection(
                  title: 'Contact',
                  rows: <_InfoRow>[
                    _InfoRow('Phone', user.phone ?? 'Not set'),
                    _InfoRow('Location', user.location ?? 'Not set'),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _InfoSection(
                  title: 'About',
                  rows: <_InfoRow>[
                    _InfoRow(
                      'Bio',
                      (user.bio == null || user.bio!.isEmpty)
                          ? 'Not set'
                          : user.bio!,
                      multiline: true,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit profile'),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: onChangePassword,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Change password'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The avatar at the top of the profile.
///
/// Falls back to the first letter of the name when no URL is set, so an
/// account with no picture does not render an empty circle.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.url});

  final String name;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final String? src = url;
    if (src == null || src.isEmpty) {
      return CircleAvatar(
        radius: 44,
        child: Text(
          name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
          style: const TextStyle(fontSize: 28),
        ),
      );
    }
    return CircleAvatar(
      radius: 44,
      backgroundImage: NetworkImage(src),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.verified, size: 16, color: AppColors.primary),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Verified Seller',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.title, required this.rows});

  final String title;
  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < rows.length; i++) ...<Widget>[
                  rows[i],
                  if (i < rows.length - 1)
                    const Divider(height: AppSpacing.md),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.multiline = false});

  final String label;
  final String value;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (multiline) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      );
    }
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.end,
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