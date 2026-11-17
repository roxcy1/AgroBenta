import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/user.dart';
import '../state/profile_controller.dart';
import '../state/profile_scope.dart';
import '../state/profile_state.dart';
import 'edit_profile_screen.dart'; // ✅ Kini ang import para sa Edit

/// A read-only view of the caller's personal details.
class PersonalInformationScreen extends StatefulWidget {
  const PersonalInformationScreen({super.key});

  @override
  State<PersonalInformationScreen> createState() =>
      _PersonalInformationScreenState();
}

class _PersonalInformationScreenState extends State<PersonalInformationScreen> {
  late final ProfileController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ProfileScope.readOf(context);
    if (_controller.state.user == null) {
      _controller.load();
    }
  }

  Future<void> _openEdit() async {
    // ✅ Gi-point sa EditProfileScreen (dili sa iyang kaugalingon)
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => const EditProfileScreen(),
        fullscreenDialog: true,
      ),
    );
    if (mounted) {
      await _controller.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal Information'),
        actions: <Widget>[
          // Disable the Edit button while the profile is still loading or
          // has failed to load. EditProfileScreen requires a non-null user,
          // so tapping Edit during a failed load would throw.
          ListenableBuilder(
            listenable: _controller,
            builder: (BuildContext context, Widget? child) {
              final bool canEdit = _controller.state.user != null;
              return TextButton(
                onPressed: canEdit ? _openEdit : null,
                child: const Text('Edit'),
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (BuildContext context, Widget? child) {
          final ProfileState state = _controller.state;

          if (state.user == null) {
            if (state.status == ProfileUiStatus.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.status == ProfileUiStatus.failed) {
              return _ErrorState(
                message: state.errorMessage ?? 'Something went wrong.',
                onRetry: _controller.load,
              );
            }
            return const SizedBox.shrink();
          }

          return _PersonalInformationBody(user: state.user!);
        },
      ),
    );
  }
}

class _PersonalInformationBody extends StatelessWidget {
  const _PersonalInformationBody({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.md,
          AppSpacing.screenGutter,
          MediaQuery.paddingOf(context).bottom + AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _InfoRow(label: 'Name', value: user.name),
                    const Divider(height: 1),
                    _InfoRow(label: 'Email', value: user.email),
                    const Divider(height: 1),
                    _InfoRow(label: 'Phone', value: user.phone ?? 'Not set'),
                    const Divider(height: 1),
                    _InfoRow(label: 'Bio', value: user.bio ?? 'Not set'),
                    const Divider(height: 1),
                    _InfoRow(
                      label: 'Account type',
                      value: user.isSeller ? 'Seller' : 'Buyer',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(value, style: theme.textTheme.bodyLarge, softWrap: true),
        ],
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
