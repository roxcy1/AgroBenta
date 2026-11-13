import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/seller_verification.dart';
import '../../../models/user.dart';
import '../../account_mode/state/account_mode.dart';
import '../../account_mode/state/account_mode_controller.dart';
import '../../account_mode/state/account_mode_scope.dart';
import '../../auth/state/auth_scope.dart';
import '../../auth/widgets/auth_scenic_header.dart';
import '../../seller_verification/state/seller_verification_controller.dart';
import '../../seller_verification/state/seller_verification_scope.dart';
import '../../seller_verification/state/seller_verification_state.dart';
import '../../seller_verification/view/seller_verification_screen.dart';
import '../state/profile_controller.dart';
import '../state/profile_scope.dart';
import '../state/profile_state.dart';
import 'address_screen.dart';
import 'change_password_screen.dart';
import 'edit_profile_screen.dart';

/// Identifies the tappable Address row in Account Settings.
///
/// A test invokes the row's `onTap` directly to reproduce a second tap that
/// lands while the first is still opening the editor.
const ValueKey<String> profileAddressTileKey = ValueKey<String>(
  'profile-address-tile',
);

/// The caller's own profile.
///
/// Reached from the signed-in shell's bottom navigation in both Buyer Mode and
/// Seller Mode. Read-only until the user taps "Personal Information", which
/// pushes the existing edit form. "Change
/// password" is offered separately because the password is not part of the
/// profile resource. Sign out lives under "Other".
///
/// Reads the profile controller once in `initState` and rebuilds from
/// [ListenableBuilder], following the same pattern as the rest of the M6
/// screens.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileController _controller;

<<<<<<< HEAD
  /// True while this screen has a pushed destination on top of it.
  ///
  /// The navigator is the wrong place to discover a double tap: by the time the
  /// second tap is hit-tested the first `push` may not have completed its
  /// transition, so two routes can stack. The flag is set *before* awaiting the
  /// push and cleared when the route pops, which makes the second call a no-op.
  bool _opening = false;
=======
  /// The destinations currently opening or open, keyed per destination.
  ///
  /// Flutter does not debounce a tap: `Navigator.push` returns immediately and
  /// the route transition does not block input, so two fast taps on the same
  /// row would otherwise stack two screens. The key is the destination rather
  /// than one shared flag, so a tap on a different row is still allowed.
  final Set<String> _opening = <String>{};
>>>>>>> 69f8cd1 (feat(mobile): improve profile screen UI and tests)

  @override
  void initState() {
    super.initState();
    _controller = ProfileScope.readOf(context);
    if (_controller.state.status == ProfileUiStatus.initial) {
      _controller.load();
    }
  }

<<<<<<< HEAD
  /// Pushes [builder] at most once, however fast the control is tapped.
  Future<void> _pushOnce(WidgetBuilder builder) async {
    if (_opening) {
      return;
    }
    setState(() => _opening = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: builder, fullscreenDialog: true),
      );
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  Future<void> _openEdit() {
    return _pushOnce((BuildContext context) => const EditProfileScreen());
  }

  Future<void> _openAddress() {
    return _pushOnce((BuildContext context) => const AddressScreen());
  }

  Future<void> _openChangePassword() {
    return _pushOnce((BuildContext context) => const ChangePasswordScreen());
=======
  /// Opens [push] once; a second call for the same [key] is ignored until the
  /// first destination has been popped.
  Future<T?> _openOnce<T>(String key, Future<T?> Function() push) async {
    if (!_opening.add(key)) {
      return null;
    }
    try {
      return await push();
    } finally {
      _opening.remove(key);
    }
  }

  Future<void> _openEdit() async {
    await _openOnce<bool>(
      'edit',
      () => Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (BuildContext context) => const EditProfileScreen(),
          fullscreenDialog: true,
        ),
      ),
    );
  }

  Future<void> _openChangePassword() async {
    await _openOnce<void>(
      'password',
      () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const ChangePasswordScreen(),
          fullscreenDialog: true,
        ),
      ),
    );
  }

  Future<void> _openHelpCenter() async {
    await _openOnce<void>(
      'help',
      () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const HelpCenterScreen(),
        ),
      ),
    );
  }

  Future<void> _openTermsAndPolicies() async {
    await _openOnce<void>(
      'terms',
      () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const TermsAndPoliciesScreen(),
        ),
      ),
    );
  }

  Future<void> _openAddressEditor(User user) async {
    await _openOnce<void>(
      'address',
      () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (BuildContext context) =>
            _EditAddressSheet(user: user, controller: _controller),
      ),
    );
>>>>>>> 69f8cd1 (feat(mobile): improve profile screen UI and tests)
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListenableBuilder(
        listenable: _controller,
        builder: (BuildContext context, Widget? child) {
          final ProfileState state = _controller.state;

          final String? success = state.successMessage;
          if (success != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(success)));
              _controller.consumeSuccess();
            });
          }

          return switch (state.status) {
            ProfileUiStatus.initial || ProfileUiStatus.loading => const Center(
              child: CircularProgressIndicator(),
            ),
            ProfileUiStatus.failed => _ErrorState(
              message: state.errorMessage ?? 'Something went wrong.',
              onRetry: _controller.load,
            ),
            _ => _ProfileBody(
              user: state.user!,
              enabled: !_opening,
              onEdit: _openEdit,
              onAddress: _openAddress,
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
    required this.enabled,
    required this.onEdit,
    required this.onAddress,
    required this.onChangePassword,
  });

  final User user;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onAddress;
  final VoidCallback onChangePassword;

  @override
  Widget build(BuildContext context) {
    // The header carries the same painted landscape, temporary logo and tagline
    // as the auth screens, so the brand treatment stays in one place. It grows
    // with the text scale and is capped, like the auth screens, so an enlarged
    // wordmark cannot overflow.
    final double textScale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, 1.8).toDouble();
    final double heroHeight =
        (MediaQuery.sizeOf(context).height * 0.26 * textScale)
            .clamp(180.0, 260.0)
            .toDouble();

    // How far the summary card rides up over the header's lower edge.
    const double overlap = 24;

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                AuthScenicHeader(height: heroHeight),
                Padding(
                  padding: EdgeInsets.only(top: heroHeight - overlap),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenGutter,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _ProfileSummaryCard(
                          user: user,
                          enabled: enabled,
                          onEdit: onEdit,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const _AccountModeCard(),
                        const SizedBox(height: AppSpacing.md),
                        _BecomeSellerCard(user: user),
                        const SizedBox(height: AppSpacing.lg),
                        _AccountSettingsSection(
                          enabled: enabled,
                          onEdit: onEdit,
                          onAddress: onAddress,
                          onChangePassword: onChangePassword,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const _OtherSection(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(
              height: MediaQuery.paddingOf(context).bottom + AppSpacing.xl,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSummaryCard extends StatelessWidget {
  const _ProfileSummaryCard({
    required this.user,
    required this.enabled,
    required this.onEdit,
  });

  final User user;
  final bool enabled;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: <Widget>[
            _Avatar(name: user.name, url: user.avatarUrl),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    user.name,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    user.email,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (user.location != null &&
                      user.location!.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: <Widget>[
                        const Icon(Icons.location_on_outlined, size: 16),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            user.location!,
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            TextButton(
              onPressed: enabled ? onEdit : null,
              child: const Text('Edit'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountModeCard extends StatelessWidget {
  const _AccountModeCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AccountModeController controller = AccountModeScope.of(context);
    final bool canUseSellerMode =
        AuthScope.of(context).state.user?.isSeller ?? false;
    final AccountMode mode = controller.mode;

    return Card(
      color: AppColors.primary.withValues(alpha: 0.08),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  mode == AccountMode.seller
                      ? Icons.storefront_outlined
                      : Icons.shopping_cart_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.md),
                Text('Account Mode', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              mode == AccountMode.seller
                  ? 'You can list and manage your livestock.'
                  : 'Browse and purchase livestock.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<AccountMode>(
              segments: <ButtonSegment<AccountMode>>[
                const ButtonSegment<AccountMode>(
                  value: AccountMode.buyer,
                  label: Text('Buyer Mode'),
                ),
                ButtonSegment<AccountMode>(
                  value: AccountMode.seller,
                  label: const Text('Seller Mode'),
                  enabled: canUseSellerMode,
                ),
              ],
              selected: <AccountMode>{mode},
              onSelectionChanged: (Set<AccountMode> selection) {
                final AccountMode next = selection.first;
                if (next == AccountMode.seller) {
                  controller.requestSellerMode();
                } else {
                  controller.select(next);
                }
              },
              showSelectedIcon: false,
              expandedInsets: EdgeInsets.zero,
            ),
            if (!canUseSellerMode) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Seller Mode becomes available after seller verification.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BecomeSellerCard extends StatefulWidget {
  const _BecomeSellerCard({required this.user});

  final User user;

  @override
  State<_BecomeSellerCard> createState() => _BecomeSellerCardState();
}

class _BecomeSellerCardState extends State<_BecomeSellerCard> {
  late final SellerVerificationController _controller;

<<<<<<< HEAD
  /// Guards the push while the route is opening, so a fast double tap cannot
  /// stack two verification screens.
  bool _opening = false;
=======
  /// Whether the verification screen is opening or open.
  ///
  /// The card owns its own pushes, so it cannot use the profile screen's
  /// guard. Without this, a fast second tap on the action stacks a second
  /// verification screen.
  bool _openingVerification = false;
>>>>>>> 69f8cd1 (feat(mobile): improve profile screen UI and tests)

  @override
  void initState() {
    super.initState();
    _controller = SellerVerificationScope.readOf(context);
    if (_controller.state.status == SellerVerificationUiStatus.initial) {
      _controller.load();
    }
  }

  Future<void> _openVerification() async {
<<<<<<< HEAD
    if (_opening) {
      return;
    }
    setState(() => _opening = true);
    try {
      await Navigator.of(context).push<void>(
=======
    if (_openingVerification) {
      return;
    }
    _openingVerification = true;
    try {
      await Navigator.of(context).push(
>>>>>>> 69f8cd1 (feat(mobile): improve profile screen UI and tests)
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              SellerVerificationScreen(accountName: widget.user.name),
        ),
      );
    } finally {
<<<<<<< HEAD
      if (mounted) {
        setState(() => _opening = false);
      }
=======
      _openingVerification = false;
>>>>>>> 69f8cd1 (feat(mobile): improve profile screen UI and tests)
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isSeller = widget.user.isSeller;

    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? child) {
        final SellerVerificationState state = _controller.state;

        return Card(
          // A pale amber tint derived from the existing warning token, the same
          // way the account-mode card derives its pale green — no new colour is
          // introduced for this one card.
          color: AppColors.warning.withValues(alpha: 0.10),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.person_add_alt_outlined),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Become a Seller', style: theme.textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Complete seller verification to start selling livestock.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (!isSeller) ...<Widget>[
                  _statusLine(state),
                  const SizedBox(height: AppSpacing.md),
                ],
                _action(state, isSeller: isSeller),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusLine(SellerVerificationState state) {
    final SellerVerification? verification = state.verification;
    if (verification == null) {
      return const SizedBox.shrink();
    }

    final (Color color, String text) = switch (verification.status) {
      SellerVerificationStatus.approved => (
        AppColors.success,
        'Verification approved',
      ),
      SellerVerificationStatus.rejected => (
        AppColors.error,
        'Verification not approved',
      ),
      SellerVerificationStatus.submitted ||
      SellerVerificationStatus.pendingReview => (
        AppColors.warning,
        'Verification under review',
      ),
    };

    return Row(
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }

  Widget _action(SellerVerificationState state, {required bool isSeller}) {
    if (isSeller) {
      return FilledButton(
        onPressed: _opening ? null : _openVerification,
        child: const Text('View verification'),
      );
    }

    if (state.status == SellerVerificationUiStatus.loading) {
      return const OutlinedButton(
        onPressed: null,
        child: Text('Checking your application…'),
      );
    }

    if (state.status == SellerVerificationUiStatus.failed) {
      return OutlinedButton(
        onPressed: _controller.load,
        child: const Text('Try again'),
      );
    }

    return switch (state.status) {
      SellerVerificationUiStatus.notSubmitted => FilledButton(
        onPressed: _opening ? null : _openVerification,
        child: const Text('Start Seller Verification'),
      ),
      SellerVerificationUiStatus.rejected => FilledButton(
        onPressed: _opening ? null : _openVerification,
        child: const Text('Resubmit Verification'),
      ),
      _ => OutlinedButton(
        onPressed: _opening ? null : _openVerification,
        child: const Text('View status'),
      ),
    };
  }
}

class _AccountSettingsSection extends StatelessWidget {
  const _AccountSettingsSection({
    required this.enabled,
    required this.onEdit,
    required this.onAddress,
    required this.onChangePassword,
  });

  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onAddress;
  final VoidCallback onChangePassword;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Account Settings', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              _SettingsTile(
                icon: Icons.person_outline,
                title: 'Personal Information',
                subtitle: 'View and update your personal details',
                enabled: enabled,
                onTap: onEdit,
              ),
              const Divider(height: 1),
              _SettingsTile(
                icon: Icons.home_outlined,
                title: 'Address',
                subtitle: 'Manage your delivery address',
                enabled: enabled,
                onTap: onAddress,
              ),
              const Divider(height: 1),
              _SettingsTile(
                icon: Icons.lock_outline,
                title: 'Change Password',
                subtitle: 'Update your account password',
                enabled: enabled,
                onTap: onChangePassword,
              ),
              const Divider(height: 1),
              _SettingsTile(
                icon: Icons.notifications_outlined,
                title: 'Notification Settings',
                subtitle: 'Manage your notification preferences',
                enabled: false,
                onTap: () {},
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OtherSection extends StatelessWidget {
  const _OtherSection();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

<<<<<<< HEAD
=======
    return InkWell(
      key: profileAddressTileKey,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _IconTile(icon: Icons.home_outlined),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Address', style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    hasAddress ? savedAddress : 'Not provided',
                    softWrap: true,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (!hasAddress) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Tap to add your delivery address',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OtherSection extends StatelessWidget {
  const _OtherSection({
    required this.onHelpAndSupport,
    required this.onTermsAndPolicies,
  });

  final VoidCallback onHelpAndSupport;
  final VoidCallback onTermsAndPolicies;

  @override
  Widget build(BuildContext context) {
>>>>>>> 69f8cd1 (feat(mobile): improve profile screen UI and tests)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Other', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              _SettingsTile(
                icon: Icons.help_outline,
                title: 'Help and Support',
                subtitle: 'Get help or contact support',
                enabled: false,
                onTap: () {},
              ),
              const Divider(height: 1),
              _SettingsTile(
                icon: Icons.description_outlined,
                title: 'Terms and Policies',
                subtitle: 'View our terms, privacy policy, and guidelines',
                enabled: false,
                onTap: () {},
              ),
              const Divider(height: 1),
              const _SignOutTile(),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListTile(
      leading: Icon(icon),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      enabled: enabled,
      onTap: enabled ? onTap : null,
    );
  }
}

class _SignOutTile extends StatelessWidget {
  const _SignOutTile();

  @override
  Widget build(BuildContext context) {
    final bool isBusy = AuthScope.of(context).state.isSigningOut;

    return ListTile(
      leading: const Icon(Icons.logout),
      title: const Text('Log Out'),
      subtitle: const Text('Sign out from your account'),
      trailing: isBusy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      enabled: !isBusy,
      onTap: isBusy ? null : () => AuthScope.of(context).signOut(),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.url});

  final String name;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final String? src = url;
    if (src == null || src.isEmpty) {
      return CircleAvatar(
        radius: 32,
        child: Text(
          name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      );
    }
    return CircleAvatar(radius: 32, backgroundImage: NetworkImage(src));
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
