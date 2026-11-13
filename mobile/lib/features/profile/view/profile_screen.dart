import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../widgets/initials_avatar.dart';
import '../../../widgets/temporary_logo.dart';
import '../../../models/seller_verification.dart';
import '../../../models/trinidad_location.dart';
import '../../../models/user.dart';
import '../../../widgets/trinidad_location_selector.dart';
import '../../account_mode/state/account_mode.dart';
import '../../account_mode/state/account_mode_controller.dart';
import '../../account_mode/state/account_mode_scope.dart';
import '../../auth/state/auth_scope.dart';
import '../../help_center/view/help_center_screen.dart';
import '../../seller_verification/state/seller_verification_controller.dart';
import '../../seller_verification/state/seller_verification_scope.dart';
import '../../seller_verification/state/seller_verification_state.dart';
import '../../seller_verification/view/seller_verification_screen.dart';
import '../../terms_and_policies/view/terms_and_policies_screen.dart';
import '../../trinidad_location/state/trinidad_location_controller.dart';
import '../../trinidad_location/state/trinidad_location_scope.dart';
import '../state/profile_controller.dart';
import '../state/profile_scope.dart';
import '../state/profile_state.dart';
import 'change_password_screen.dart';
import 'edit_profile_screen.dart';

/// The caller's own profile.
///
/// Reached from the signed-in shell's bottom navigation in both Buyer Mode and
/// Seller Mode. Name and email are read-only until the user taps "Personal
/// Information", which pushes the existing edit form. Address is displayed and
/// edited in its own section. "Change password" is offered separately because
/// the password is not part of the profile resource. Sign out lives under
/// "Other".
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
  bool _openingHelpCenter = false;
  bool _openingTermsAndPolicies = false;

  @override
  void initState() {
    super.initState();
    _controller = ProfileScope.readOf(context);
    if (_controller.state.status == ProfileUiStatus.initial) {
      _controller.load();
    }
  }

  Future<void> _openEdit() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => const EditProfileScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _openChangePassword() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const ChangePasswordScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _openHelpCenter() async {
    if (_openingHelpCenter) return;
    _openingHelpCenter = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const HelpCenterScreen(),
        ),
      );
    } finally {
      _openingHelpCenter = false;
    }
  }

  Future<void> _openTermsAndPolicies() async {
    if (_openingTermsAndPolicies) return;
    _openingTermsAndPolicies = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const TermsAndPoliciesScreen(),
        ),
      );
    } finally {
      _openingTermsAndPolicies = false;
    }
  }

  Future<void> _openAddressEditor(User user) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) =>
          _EditAddressSheet(user: user, controller: _controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // A white page: the approved design sets the account header and the
      // mode switch straight on the surface, with only the lists boxed.
      backgroundColor: AppColors.surface,
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
              onEdit: _openEdit,
              onEditAddress: () => _openAddressEditor(state.user!),
              onChangePassword: _openChangePassword,
              onHelpAndSupport: _openHelpCenter,
              onTermsAndPolicies: _openTermsAndPolicies,
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
    required this.onEditAddress,
    required this.onChangePassword,
    required this.onHelpAndSupport,
    required this.onTermsAndPolicies,
  });

  final User user;
  final VoidCallback onEdit;
  final VoidCallback onEditAddress;
  final VoidCallback onChangePassword;
  final VoidCallback onHelpAndSupport;
  final VoidCallback onTermsAndPolicies;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // A compact white header: the logo (which carries the wordmark) and
          // the screen title, like every other tab.
          Container(
            height: AppSizes.appBarHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenGutter,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: <Widget>[
                const TemporaryLogo(size: 30),
                const SizedBox(width: AppSpacing.sm),
                Text('Profile', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
          Expanded(
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
                  _ProfileSummaryCard(user: user, onEdit: onEdit),
                  const SizedBox(height: AppSpacing.md),
                  const _AccountModeCard(),
                  const SizedBox(height: AppSpacing.md),
                  // Only for accounts that are not sellers yet. Once the
                  // account is verified there is nothing left to apply for,
                  // so the whole card goes, not just its button.
                  if (!user.isSeller) ...<Widget>[
                    _BecomeSellerCard(user: user),
                    const SizedBox(height: AppSpacing.lg),
                  ] else
                    const SizedBox(height: AppSpacing.xs),
                  _AccountSettingsSection(
                    location: user.location,
                    onEdit: onEdit,
                    onEditAddress: onEditAddress,
                    onChangePassword: onChangePassword,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _OtherSection(
                    onHelpAndSupport: onHelpAndSupport,
                    onTermsAndPolicies: onTermsAndPolicies,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSummaryCard extends StatelessWidget {
  const _ProfileSummaryCard({required this.user, required this.onEdit});

  final User user;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // No card: the avatar, name and email sit straight on the page.
    return Row(
      children: <Widget>[
        InitialsAvatar(name: user.name, imageUrl: user.avatarUrl, radius: 36),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                user.name,
                style: theme.textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xxxs),
              Text(
                user.email,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        TextButton(onPressed: onEdit, child: const Text('Edit')),
      ],
    );
  }
}

class _EditAddressSheet extends StatefulWidget {
  const _EditAddressSheet({required this.user, required this.controller});

  final User user;
  final ProfileController controller;

  @override
  State<_EditAddressSheet> createState() => _EditAddressSheetState();
}

class _EditAddressSheetState extends State<_EditAddressSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TrinidadLocationController _locationCatalog;
  TrinidadLocation? _location;
  String? _legacyAddress;
  String? _pendingAddress;
  bool _locationTouched = false;
  Map<String, List<String>> _displayedErrors = const <String, List<String>>{};

  @override
  void initState() {
    super.initState();
    _locationCatalog = TrinidadLocationScope.readOf(context);
    _pendingAddress = widget.user.location?.trim();
    _restoreQueuedLocation();
    _locationCatalog.addListener(_onLocationCatalogChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _locationCatalog.ensureLoaded();
    });
  }

  @override
  void dispose() {
    _locationCatalog.removeListener(_onLocationCatalogChanged);
    super.dispose();
  }

  void _restoreQueuedLocation() {
    final TrinidadLocationCatalog? catalog = _locationCatalog.state.catalog;
    if (catalog == null) return;

    final String? raw = _pendingAddress;
    final TrinidadLocation? parsed = catalog.parseAddress(raw);
    _location = parsed;
    _legacyAddress = raw != null && raw.isNotEmpty && parsed == null
        ? raw
        : null;
  }

  void _onLocationCatalogChanged() {
    if (_pendingAddress != null && _locationCatalog.state.isReady && mounted) {
      setState(_restoreQueuedLocation);
    }
  }

  void _onLocationChanged(TrinidadLocation? value) {
    setState(() {
      _location = value;
      _legacyAddress = null;
      _pendingAddress = null;
      _locationTouched = true;
    });
  }

  void _revealServerFieldErrors(Map<String, List<String>> errors) {
    if (mapEquals(errors, _displayedErrors)) return;
    _displayedErrors = Map<String, List<String>>.of(errors);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _formKey.currentState?.validate();
    });
  }

  Future<void> _saveAddress() async {
    if (!_locationTouched || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final TrinidadLocationCatalog? catalog = _locationCatalog.state.catalog;
    if (catalog == null) return;

    final String location =
        _location?.formattedAddress(
          municipality: catalog.municipality,
          province: catalog.province,
        ) ??
        '';
    final bool saved = await widget.controller.save(location: location);
    if (saved && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.lg,
            AppSpacing.screenGutter,
            AppSpacing.lg,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (BuildContext context, Widget? child) {
                  final ProfileState state = widget.controller.state;
                  final bool canSave =
                      !state.isBusy &&
                      _locationTouched &&
                      _locationCatalog.state.catalog != null;
                  _revealServerFieldErrors(state.fieldErrors);

                  return Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          'Edit address',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'Choose a barangay and optionally add a street or purok.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        if (state.errorMessage != null) ...<Widget>[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            state.errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        TrinidadLocationSelector(
                          value: _location,
                          legacyAddress: _legacyAddress,
                          maxFormattedLength:
                              TrinidadLocation.profileAddressMax,
                          isRequired: false,
                          enabled: !state.isBusy,
                          externalError: state.errorFor('location'),
                          onChanged: _onLocationChanged,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          children: <Widget>[
                            OutlinedButton(
                              onPressed: state.isBusy
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: canSave ? _saveAddress : null,
                              child: state.isBusy
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Save address'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _GroupLabel('Account Mode'),
        const SizedBox(height: AppSpacing.xs),
        // A grey track with the selected half raised in white, as in the
        // approved design, rather than Material's outlined pill.
        Container(
          padding: const EdgeInsets.all(AppSpacing.xxs),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: SegmentedButton<AccountMode>(
            style: ButtonStyle(
              visualDensity: VisualDensity.standard,
              backgroundColor: WidgetStateProperty.resolveWith<Color?>(
                (Set<WidgetState> states) =>
                    states.contains(WidgetState.selected)
                    ? AppColors.surface
                    : Colors.transparent,
              ),
              foregroundColor: WidgetStateProperty.resolveWith<Color?>(
                (Set<WidgetState> states) =>
                    states.contains(WidgetState.disabled)
                    ? AppColors.textSecondary.withValues(alpha: 0.5)
                    : states.contains(WidgetState.selected)
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
              side: const WidgetStatePropertyAll<BorderSide>(
                BorderSide(color: Colors.transparent),
              ),
              shape: WidgetStatePropertyAll<OutlinedBorder>(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              textStyle: WidgetStatePropertyAll<TextStyle?>(
                theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
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
        if (!canUseSellerMode) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Seller Mode becomes available after seller verification.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
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

  @override
  void initState() {
    super.initState();
    _controller = SellerVerificationScope.readOf(context);
    if (_controller.state.status == SellerVerificationUiStatus.initial) {
      _controller.load();
    }
  }

  void _openVerification() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            SellerVerificationScreen(accountName: widget.user.name),
      ),
    );
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
          color: AppColors.primarySurface,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Become a Seller',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    const Icon(
                      Icons.storefront_outlined,
                      size: 20,
                      color: AppColors.primary,
                    ),
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
        onPressed: _openVerification,
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
        onPressed: _openVerification,
        child: const Text('Start Seller Verification'),
      ),
      SellerVerificationUiStatus.rejected => FilledButton(
        onPressed: _openVerification,
        child: const Text('Resubmit Verification'),
      ),
      _ => OutlinedButton(
        onPressed: _openVerification,
        child: const Text('View status'),
      ),
    };
  }
}

class _AccountSettingsSection extends StatelessWidget {
  const _AccountSettingsSection({
    required this.location,
    required this.onEdit,
    required this.onEditAddress,
    required this.onChangePassword,
  });

  final String? location;
  final VoidCallback onEdit;
  final VoidCallback onEditAddress;
  final VoidCallback onChangePassword;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _GroupLabel('Account Settings'),
        const SizedBox(height: AppSpacing.xs),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              _SettingsTile(
                icon: Icons.person_outline,
                title: 'Personal Information',
                subtitle: 'View and update your personal details',
                onTap: onEdit,
              ),
              const Divider(height: 1),
              _AddressSettingsTile(location: location, onTap: onEditAddress),
              const Divider(height: 1),
              _SettingsTile(
                icon: Icons.lock_outline,
                title: 'Change Password',
                subtitle: 'Update your account password',
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

class _AddressSettingsTile extends StatelessWidget {
  const _AddressSettingsTile({required this.location, required this.onTap});

  final String? location;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String savedAddress = location?.trim() ?? '';
    final bool hasAddress = savedAddress.isNotEmpty;

    return InkWell(
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _GroupLabel('Other'),
        const SizedBox(height: AppSpacing.xs),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              _SettingsTile(
                icon: Icons.help_outline,
                title: 'Help and Support',
                subtitle: 'Get help or contact support',
                onTap: onHelpAndSupport,
              ),
              const Divider(height: 1),
              _SettingsTile(
                icon: Icons.description_outlined,
                title: 'Terms and Policies',
                subtitle: 'View our terms, privacy policy, and guidelines',
                onTap: onTermsAndPolicies,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Log Out stands alone, in red, so it is never tapped by habit.
        const Card(margin: EdgeInsets.zero, child: _SignOutTile()),
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
      leading: _IconTile(icon: icon),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(
        Icons.chevron_right,
        size: 20,
        color: AppColors.textSecondary,
      ),
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

    final ThemeData theme = Theme.of(context);

    return ListTile(
      leading: const _IconTile(icon: Icons.logout, danger: true),
      title: Text(
        'Log Out',
        style: theme.textTheme.titleSmall?.copyWith(color: AppColors.error),
      ),
      subtitle: Text(
        'Sign out from your account',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      trailing: isBusy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      enabled: !isBusy,
      onTap: isBusy ? null : () => AuthScope.of(context).signOut(),
    );
  }
}

/// The small grey heading above a group of rows.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// The tinted square that carries a row's icon.
class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, this.danger = false});

  final IconData icon;

  /// Red on a pale red tile, for the one destructive row.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color accent = danger ? AppColors.error : AppColors.primary;

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: danger
            ? AppColors.error.withValues(alpha: 0.10)
            : AppColors.primarySurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(icon, size: 19, color: accent),
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
