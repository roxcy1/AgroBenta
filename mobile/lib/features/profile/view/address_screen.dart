import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/trinidad_location.dart';
import '../../../models/user.dart';
import '../../../widgets/trinidad_location_selector.dart';
import '../../trinidad_location/state/trinidad_location_controller.dart';
import '../../trinidad_location/state/trinidad_location_scope.dart';
import '../state/profile_controller.dart';
import '../state/profile_scope.dart';
import '../state/profile_state.dart';

/// The caller's saved profile address.
///
/// There is one address per account. It lives in the profile's `location`
/// string and is optional, so this screen both shows it and edits it — there is
/// no address book and no delivery-address record. The value uses the shared
/// Trinidad barangay catalog and the canonical format described in DEC-07.
///
/// ## Legacy values
///
/// A stored address that cannot be matched to the catalog is not rewritten on
/// sight. It is shown unchanged, and the user must choose a barangay to replace
/// it. That is the same rule `EditProfileScreen` applies, and it is why this
/// screen keeps `_legacyLocation` separate from `_location`.
///
/// ## Saving
///
/// Only a changed address is sent, through [ProfileController.save], which does
/// `PUT /profile` with only the `location` field. An unchanged address simply
/// closes the screen. Clearing the selection sends an empty value, which the
/// server stores as `null`.
class AddressScreen extends StatefulWidget {
  const AddressScreen({super.key});

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final ProfileController _controller;
  late final TrinidadLocationController _locationCatalog;
  late final User _initial;

  TrinidadLocation? _location;
  String? _legacyLocation;
  String? _pendingLocation;
  bool _locationTouched = false;

  /// The field errors currently on screen, so a repeat of the same server error
  /// does not re-validate for nothing.
  Map<String, List<String>> _displayedErrors = const <String, List<String>>{};

  @override
  void initState() {
    super.initState();
    _controller = ProfileScope.readOf(context);
    _locationCatalog = TrinidadLocationScope.readOf(context);
    _locationCatalog.addListener(_onLocationCatalogChanged);
    _initial =
        _controller.state.user ??
        (throw StateError('AddressScreen opened without a loaded profile.'));

    _queueInitialLocation(_initial.location);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _locationCatalog.ensureLoaded();
    });
  }

  /// A `422` arrives after the last validation, so the field would never show
  /// the server's message without re-running it. This is the same rule
  /// `EditProfileScreen` applies to its fields.
  void _revealServerFieldErrors(Map<String, List<String>> errors) {
    if (mapEquals(errors, _displayedErrors)) {
      return;
    }
    _displayedErrors = Map<String, List<String>>.of(errors);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _formKey.currentState?.validate();
      }
    });
  }

  @override
  void dispose() {
    _locationCatalog.removeListener(_onLocationCatalogChanged);
    super.dispose();
  }

  void _queueInitialLocation(String? raw) {
    _pendingLocation = raw?.trim();
    _restoreQueuedLocation();
  }

  void _restoreQueuedLocation() {
    final String? raw = _pendingLocation;
    final TrinidadLocationCatalog? catalog = _locationCatalog.state.catalog;
    final TrinidadLocation? parsed = catalog?.parseAddress(raw);
    _location = parsed;
    _legacyLocation = raw != null && raw.isNotEmpty && parsed == null
        ? raw
        : null;
  }

  void _onLocationCatalogChanged() {
    if (_pendingLocation != null && _locationCatalog.state.isReady && mounted) {
      setState(_restoreQueuedLocation);
    }
  }

  void _onLocationChanged(TrinidadLocation? value) {
    setState(() {
      _location = value;
      _legacyLocation = null;
      _pendingLocation = null;
      _locationTouched = true;
    });
    _controller.clearError();
  }

  /// The address to save: the formatted selection when touched, otherwise the
  /// stored value. An empty result clears the address.
  String _nextAddress(TrinidadLocationCatalog catalog) {
    if (!_locationTouched) {
      return _initial.location?.trim() ?? '';
    }
    return _location?.formattedAddress(
          municipality: catalog.municipality,
          province: catalog.province,
        ) ??
        '';
  }

  Future<void> _save() async {
    final ProfileState state = _controller.state;
    if (state.isBusy) {
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final TrinidadLocationCatalog? catalog = _locationCatalog.state.catalog;
    if (catalog == null) {
      return;
    }

    final String next = _nextAddress(catalog);
    if (next == (_initial.location?.trim() ?? '')) {
      Navigator.of(context).pop();
      return;
    }

    final bool saved = await _controller.save(location: next);
    if (saved && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Address')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? child) {
            final ProfileState state = _controller.state;
            final bool isSaving = state.status == ProfileUiStatus.saving;
            final bool catalogReady = _locationCatalog.state.isReady;
            final ThemeData theme = Theme.of(context);

            _revealServerFieldErrors(state.fieldErrors);

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              children: <Widget>[
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          (_initial.location ?? '').isEmpty
                              ? 'No address saved yet.'
                              : 'Your saved address is shown below. '
                                    'You can change or clear it.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (state.errorMessage != null) ...<Widget>[
                          Text(
                            state.errorMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: TrinidadLocationSelector(
                            value: _location,
                            legacyAddress: _legacyLocation,
                            maxFormattedLength:
                                TrinidadLocation.profileAddressMax,
                            isRequired: false,
                            enabled: !isSaving,
                            externalError: state.errorFor('location'),
                            onChanged: _onLocationChanged,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        FilledButton(
                          onPressed: isSaving || !catalogReady ? null : _save,
                          child: isSaving
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
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
