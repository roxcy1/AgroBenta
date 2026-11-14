import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../features/profile/state/profile_scope.dart';
import '../../../models/ai_price_estimate.dart';
import '../../../models/listing.dart';
import '../../../models/livestock_type.dart';
import '../../../widgets/field_label.dart';
import '../../../models/trinidad_location.dart';
import '../../livestock_types/state/livestock_types_controller.dart';
import '../../livestock_types/state/livestock_types_scope.dart';
import '../../livestock_types/state/livestock_types_state.dart';
import '../../trinidad_location/state/trinidad_location_controller.dart';
import '../../trinidad_location/state/trinidad_location_scope.dart';
import '../state/listing_photo_item.dart';
import '../state/seller_listing_controller.dart';
import '../state/seller_listing_draft.dart';
import '../state/seller_listing_scope.dart';
import '../state/seller_listing_state.dart';
import '../widgets/listing_photo_grid.dart';
import 'seller_listing_input_formatters.dart';
import 'seller_listing_views.dart';
import 'seller_listing_validators.dart';
import '../../../widgets/notice_banner.dart';
import '../../../widgets/section_card.dart';
import '../../../widgets/trinidad_location_selector.dart';

/// Which Stepper step shows each server-validated field.
///
/// A `422` names fields, not steps, and the field that failed may not be on the
/// step the save button was pressed on. This is the only place that mapping is
/// written down.
const Map<String, int> _fieldStep = <String, int>{
  'photos': 0,
  'livestock_type': 0,
  'breed': 0,
  'age_value': 0,
  'age_unit': 0,
  'weight_value': 0,
  'weight_unit': 0,
  'quantity': 1,
  'total_quantity': 1,
  'asking_price': 1,
  'location': 1,
  'gender': 1,
  'health_status': 1,
  'vaccination': 1,
  'short_description': 1,
  'additional_notes': 1,
};

/// Create or edit a listing.
///
/// The same screen for both. The contract's create and update differ only in
/// which fields are required and in the URL, and the form's own validation
/// already mirrors the create rules, so a separate edit screen would be the same
/// screen with a button and an `if` changed. The only real difference is the
/// title, the endpoint and whether the record being edited can be changed at all.
///
/// ## What the form cannot do
///
/// It cannot change a listing's **status**, and that is not a missing control —
/// it is the shape of the feature. A seller creates a draft and submits it;
/// approval and everything after it belong to an administrator. So there is no
/// status control here, and no field that could express one.
///
/// It also cannot change how a listing is published; photos are managed in the
/// composer on the first step and uploaded once the draft exists.
class SellerListingFormScreen extends StatefulWidget {
  const SellerListingFormScreen({this.listing, super.key});

  /// The listing being edited, or `null` to create one.
  final Listing? listing;

  @override
  State<SellerListingFormScreen> createState() =>
      _SellerListingFormScreenState();
}

class _SellerListingFormScreenState extends State<SellerListingFormScreen> {
  final TextEditingController _breed = TextEditingController();
  final TextEditingController _ageValue = TextEditingController();
  final TextEditingController _weightValue = TextEditingController();
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _askingPrice = TextEditingController();
  final TextEditingController _healthStatus = TextEditingController();
  final TextEditingController _vaccination = TextEditingController();
  final TextEditingController _shortDescription = TextEditingController();
  final TextEditingController _additionalNotes = TextEditingController();

  String? _livestockType;
  String? _ageUnit;
  String _ageInformation = 'known';
  String? _gender;
  String? _weightUnit;
  String _weightInformation = 'measured';
  bool _clearBreed = false;

  late final LivestockTypesController _catalog;
  late final TrinidadLocationController _locationCatalog;
  TrinidadLocation? _selectedLocation;
  String? _legacyLocation;
  String? _pendingLocation;
  String _initialLocation = '';
  bool _locationWasTouched = false;

  int _step = 0;

  /// The form holding every step's fields.
  ///
  /// One form for the whole Stepper rather than one per step, so every field the
  /// Stepper has built shares a single validation state. Auto-validation is set
  /// per field instead of on this form, so typing in one step cannot light up
  /// errors in another.
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  /// The age field, validated on its own when the unit changes.
  ///
  /// The age limit depends on the unit, so a new unit can make an already-typed
  /// age invalid (300 months is valid; 300 years is not). Validating this one
  /// field avoids the whole-form `validate()` that would also put errors on
  /// fields the seller has not touched.
  final GlobalKey<FormFieldState<String>> _ageValueFieldKey =
      GlobalKey<FormFieldState<String>>();

  late final SellerListingController _controller;
  bool _submitting = false;

  /// A local validation message for the AI-only inputs.
  ///
  /// These fields are optional for saving a normal listing, so they cannot be
  /// made into form-wide required fields without changing the listing contract.
  String? _suggestionInputMessage;

  /// Incremented whenever an input that feeds the model changes. It lets the
  /// form discard a reply that belongs to values the seller has already edited.
  int _suggestionInputRevision = 0;

  /// The listing this form created, if a save succeeded but photo work did not.
  ///
  /// The form stays open on an upload failure so the seller can retry. The next
  /// save must therefore update this record rather than create a second draft.
  Listing? _saved;

  bool get _isEditing => widget.listing != null;

  /// Whether the record being edited predates the required age.
  ///
  /// A legacy draft may still be saved without backfilling an untouched
  /// measurement; submission enforces completeness. A new listing, or a listing
  /// that already had a complete value, does not get this exemption.
  bool get _legacyAgeIncomplete {
    final Listing? listing = widget.listing;
    return listing != null &&
        (listing.ageValue == null || listing.ageUnit == null);
  }

  /// Whether the record being edited predates the required weight.
  bool get _legacyWeightIncomplete {
    final Listing? listing = widget.listing;
    return listing != null &&
        (listing.weightValue == null || listing.weightUnit == null);
  }

  void _onStepContinue() {
    // Only the step being left is checked. A step further on is still empty at
    // this point, so checking it here would make the first Continue impossible.
    if (_stepHasErrors(_step)) {
      // The messages exist only once a field is validated, and a field the
      // seller has not typed in never auto-validates. Continuing is an explicit
      // request to move on, so validating is what makes its error visible.
      _formKey.currentState?.validate();
      return;
    }
    if (_step < 2) {
      setState(() => _step++);
    }
  }

  void _onStepCancel() {
    if (_step > 0) {
      setState(() => _step--);
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = SellerListingScope.readOf(context);
    _catalog = LivestockTypesScope.readOf(context);
    _locationCatalog = TrinidadLocationScope.readOf(context);

    final Listing? listing = widget.listing;
    if (listing != null) {
      final SellerListingDraft draft = SellerListingDraft.fromListing(listing);
      _initialLocation = draft.location;
      _queueInitialLocation(draft.location);
      _livestockType = draft.livestockType.trim().isEmpty
          ? null
          : draft.livestockType;
      _breed.text = draft.breed;
      _ageValue.text = draft.ageValue;
      _ageUnit = draft.ageUnit;
      _ageInformation = draft.ageInformation;
      _gender = draft.gender;
      _weightValue.text = draft.weightValue;
      _weightUnit = draft.weightUnit;
      _weightInformation = draft.weightInformation;
      _quantity.text = draft.quantity;
      _askingPrice.text = draft.askingPrice;
      _healthStatus.text = draft.healthStatus;
      _vaccination.text = draft.vaccination;
      _shortDescription.text = draft.shortDescription;
      _additionalNotes.text = draft.additionalNotes;
    } else {
      // Prefill only from an already-loaded profile snapshot. The selector
      // remains editable, and creating a listing never starts a separate
      // profile request.
      final String? profileLocation = ProfileScope.maybeReadOf(
        context,
      )?.state.user?.location;
      if (profileLocation != null && profileLocation.trim().isNotEmpty) {
        _initialLocation = profileLocation;
        _queueInitialLocation(profileLocation);
      }
    }

    // These three fields are model inputs. Listening here clears a suggestion
    // as soon as the seller edits one, without adding a second onChanged
    // parameter to the shared text-field widget.
    _breed.addListener(_onSuggestionInputChanged);
    _ageValue.addListener(_onSuggestionInputChanged);
    _weightValue.addListener(_onSuggestionInputChanged);
    // Quantity and asking price are listing totals, not model inputs. They
    // clear a stale input message but never discard a per-head estimate.
    _quantity.addListener(_onSuggestionDraftInputChanged);
    _askingPrice.addListener(_onSuggestionDraftInputChanged);
    _locationCatalog.addListener(_handleLocationCatalogChanged);

    // Seed the photo composer from the server-served URLs when editing, or
    // leave it empty for a new draft. Photos upload once the listing exists.
    //
    // Deferred to a post-frame callback: startPhotoComposer notifies the
    // controller's listeners, and notifying during this build (initState)
    // throws "setState() or markNeedsBuild() called during build".
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The controller is session-scoped. A result from a previous form must
      // never appear beside this form's values.
      _controller.clearPriceSuggestion();
      _catalog.ensureLoaded();
      _locationCatalog.ensureLoaded();
      _controller.startPhotoComposer(
        widget.listing?.id,
        widget.listing?.photos ?? const <String>[],
      );
    });
  }

  void _queueInitialLocation(String raw) {
    _pendingLocation = raw.trim();
    _restoreQueuedLocation();
  }

  void _restoreQueuedLocation() {
    final String? raw = _pendingLocation;
    final TrinidadLocationCatalog? catalog = _locationCatalog.state.catalog;
    final TrinidadLocation? parsed = catalog?.parseAddress(raw);
    _selectedLocation = parsed;
    _legacyLocation = raw != null && raw.isNotEmpty && parsed == null
        ? raw
        : null;
  }

  void _handleLocationCatalogChanged() {
    if (_pendingLocation != null && _locationCatalog.state.isReady && mounted) {
      setState(_restoreQueuedLocation);
    }
  }

  void _handleLocationChanged(TrinidadLocation? value) {
    setState(() {
      _selectedLocation = value;
      _legacyLocation = null;
      _pendingLocation = null;
      _locationWasTouched = true;
    });
    _onSuggestionDraftInputChanged();
  }

  String _locationForSave() {
    final TrinidadLocationCatalog? catalog = _locationCatalog.state.catalog;
    final String? formatted = catalog == null
        ? null
        : _selectedLocation?.formattedAddress(
            municipality: catalog.municipality,
            province: catalog.province,
          );
    if (formatted != null) return formatted;
    if (_isEditing && !_locationWasTouched) return _initialLocation;
    return '';
  }

  String? _validateLocation() {
    final TrinidadLocationCatalog? catalog = _locationCatalog.state.catalog;
    final String? formatted = catalog == null
        ? null
        : _selectedLocation?.formattedAddress(
            municipality: catalog.municipality,
            province: catalog.province,
          );
    if (formatted != null) return validateListingLocation(formatted);

    // Unmapped historical values may be preserved during an unrelated edit,
    // but an explicit location edit needs a barangay selection.
    if (_isEditing && !_locationWasTouched && _initialLocation.isNotEmpty) {
      return validateListingLocation(_initialLocation);
    }
    return 'Select a barangay.';
  }

  @override
  void dispose() {
    _breed.removeListener(_onSuggestionInputChanged);
    _ageValue.removeListener(_onSuggestionInputChanged);
    _weightValue.removeListener(_onSuggestionInputChanged);
    _quantity.removeListener(_onSuggestionDraftInputChanged);
    _askingPrice.removeListener(_onSuggestionDraftInputChanged);
    _locationCatalog.removeListener(_handleLocationCatalogChanged);
    _breed.dispose();
    _ageValue.dispose();
    _weightValue.dispose();
    _quantity.dispose();
    _askingPrice.dispose();
    _healthStatus.dispose();
    _vaccination.dispose();
    _shortDescription.dispose();
    _additionalNotes.dispose();
    super.dispose();
  }

  SellerListingDraft _buildDraft() => SellerListingDraft(
    livestockType: _livestockType ?? '',
    breed: _breed.text,
    clearBreed: _clearBreed,
    ageValue: _ageValue.text,
    ageUnit: _ageUnit,
    ageInformation: _ageInformation,
    gender: _gender,
    weightValue: _weightValue.text,
    weightUnit: _weightUnit,
    weightInformation: _weightInformation,
    quantity: _quantity.text,
    askingPrice: _askingPrice.text,
    location: _locationForSave(),
    healthStatus: _healthStatus.text,
    vaccination: _vaccination.text,
    shortDescription: _shortDescription.text,
    additionalNotes: _additionalNotes.text,
  );

  LivestockType? _typeForValue(List<LivestockType> types, String value) {
    for (final LivestockType type in types) {
      if (type.value == value) {
        return type;
      }
    }
    return null;
  }

  LivestockType? _selectedType(List<LivestockType> types) {
    final String? value = _livestockType;
    return value == null ? null : _typeForValue(types, value);
  }

  String? _selectedLivestockType(List<LivestockType> types) =>
      _selectedType(types)?.value;

  void _selectLivestockType(String? value, List<LivestockType> types) {
    LivestockType? type;
    for (final LivestockType item in types) {
      if (item.value == value) {
        type = item;
        break;
      }
    }

    setState(() {
      _livestockType = value;
      if (type == null ||
          (_breed.text.isNotEmpty && !type.breeds.contains(_breed.text))) {
        _breed.clear();
        _clearBreed = false;
      }
    });
    _onSuggestionInputChanged();
  }

  List<String> _breedOptions(LivestockType type) {
    final List<String> breeds = List<String>.of(type.breeds);
    final Listing? original = widget.listing;
    if (original != null &&
        _livestockType == original.livestockType &&
        _breed.text == original.breed &&
        _breed.text.isNotEmpty &&
        !breeds.contains(_breed.text)) {
      // Historical breeds remain editable without being silently rewritten.
      breeds.add(_breed.text);
    }
    return breeds;
  }

  /// Whether [step] has at least one client-side error.
  bool _stepHasErrors(int step) =>
      _localErrorsForStep(step).any((String? error) => error != null);

  /// The first step that still has an invalid field, or `null` when the form is
  /// valid. Steps are checked in order, which is also the order the seller walks
  /// them in.
  int? _firstInvalidStep() {
    for (int step = 0; step <= 1; step++) {
      if (_stepHasErrors(step)) {
        return step;
      }
    }
    return null;
  }

  /// Every client-side error the form can report for [step], in field order.
  ///
  /// The validator functions are called directly rather than through the
  /// `FormState`, so the step to open is known before anything is rendered.
  List<String?> _localErrorsForStep(int step) {
    switch (step) {
      case 0:
        return <String?>[
          validateLivestockType(
            _catalog.state.isReady
                ? _selectedLivestockType(_catalog.state.types)
                : null,
          ),
          validateBreed(_breed.text),
          _legacyAgeIncomplete && _ageValue.text.trim().isEmpty
              ? null
              : validateAgeValue(_ageValue.text, unit: _ageUnit),
          _legacyAgeIncomplete && _ageValue.text.trim().isEmpty
              ? null
              : validateAgeUnit(_ageUnit),
          _legacyWeightIncomplete && _weightValue.text.trim().isEmpty
              ? null
              : validateWeightValue(_weightValue.text),
          _legacyWeightIncomplete && _weightValue.text.trim().isEmpty
              ? null
              : validateWeightUnit(_weightUnit),
        ];
      case 1:
        return <String?>[
          validateQuantity(_quantity.text),
          validateAskingPrice(_askingPrice.text),
          _validateLocation(),
          validateOptionalShortText(_healthStatus.text),
          validateOptionalShortText(_vaccination.text),
          validateOptionalShortText(_shortDescription.text),
          validateAdditionalNotes(_additionalNotes.text),
        ];
      default:
        return const <String?>[];
    }
  }

  /// The first step a server-reported error belongs to, or `null` when the `422`
  /// named no field this form shows.
  int? _firstStepWithServerError(Map<String, List<String>> errors) {
    int? first;
    for (final String field in errors.keys) {
      final int? step = _fieldStep[field];
      if (step != null && (first == null || step < first)) {
        first = step;
      }
    }
    return first;
  }

  Future<void> _save() async {
    final Listing? saved = await _persistDraft();
    if (!mounted || saved == null) {
      return;
    }

    _saved = saved;

    // Upload any locally-picked photos that were not yet stored. The server
    // returns the whole listing, so the composer is rebuilt from served URLs
    // and client and server agree. A previously failed batch is resent too.
    final bool hasPhotoWork = _controller.photos.any(
      (ListingPhotoItem p) =>
          p.status == ListingPhotoStatus.pending ||
          p.status == ListingPhotoStatus.failed,
    );
    if (hasPhotoWork) {
      final bool uploaded = await _controller.uploadComposerPhotos(saved.id);
      if (!mounted) {
        return;
      }
      if (!uploaded) {
        // Stay on the form: the failed tiles and their retry controls are on
        // step 0, so that is where the seller needs to be.
        setState(() => _step = 0);
        return;
      }
    }
    // The caller needs the record it just wrote, to open or refresh with.
    if (mounted) Navigator.of(context).pop(saved);
  }

  /// Validates and persists the current form without deciding what to do next.
  ///
  /// Shared by the normal Save action and the AI suggestion action so the two
  /// cannot drift. Returns `null` when validation or the request failed, in
  /// which case the existing per-field error handling has already run.
  Future<Listing?> _persistDraft() async {
    if (!_catalog.state.isReady) {
      setState(() => _step = 0);
      if (_catalog.state.hasFailed) {
        _catalog.retry();
      }
      return null;
    }

    final int? invalidStep = _firstInvalidStep();
    if (invalidStep != null) {
      setState(() => _step = invalidStep);
      // Validated after the frame that opened the bad step, so the messages are
      // painted on the fields the seller is now looking at.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _formKey.currentState?.validate();
      });
      return null;
    }

    final SellerListingDraft draft = _buildDraft();
    final Listing? target = _saved ?? widget.listing;

    setState(() => _submitting = true);
    _controller.clearActionMessage();

    final Listing? saved = target != null
        ? await _controller.update(target.id, draft)
        : await _controller.create(draft);

    if (!mounted) {
      return null;
    }
    setState(() => _submitting = false);

    if (saved != null) {
      _saved = saved;
      return saved;
    }

    // A `422` arrives as per-field messages. Re-validating after this frame
    // folds the server's message into the field it names (the field validator
    // gives the server precedence), and the step that owns the first one is
    // opened so the message is not hidden behind a Stepper tab.
    final Map<String, List<String>> serverErrors =
        _controller.state.validationErrors;
    if (serverErrors.isEmpty) {
      return null;
    }
    final int? errorStep = _firstStepWithServerError(serverErrors);
    if (errorStep != null && errorStep != _step) {
      setState(() => _step = errorStep);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _formKey.currentState?.validate();
    });
    return null;
  }

  /// Saves the current form as a draft, then asks the server for an estimate.
  ///
  /// The draft has to exist first: the endpoint is keyed by listing id and reads
  /// the persisted record, not the form. Keeping the form open after the save is
  /// deliberate — the result belongs beside Asking Price, and the seller may
  /// choose to use it, ignore it, or edit further.
  Future<void> _suggestPrice() async {
    if (_submitting ||
        _controller.state.isActioning ||
        !_canRequestPriceSuggestion) {
      return;
    }

    final String? inputError = _suggestionInputError();
    if (inputError != null) {
      setState(() => _suggestionInputMessage = inputError);
      return;
    }

    setState(() => _suggestionInputMessage = null);
    final int revision = _suggestionInputRevision;
    final Listing? saved = await _persistDraft();
    if (!mounted || saved == null) {
      return;
    }

    if (revision != _suggestionInputRevision) {
      setState(() {
        _suggestionInputMessage =
            'Your details changed while the draft was saving. Request the '
            'suggestion again.';
      });
      return;
    }

    await _controller.requestPriceSuggestion(saved.id);
    if (!mounted) {
      return;
    }

    if (revision != _suggestionInputRevision) {
      _controller.clearPriceSuggestion();
      setState(() {
        _suggestionInputMessage =
            'Your details changed while the suggestion was being generated. '
            'Request it again for the updated values.';
      });
    }
  }

  /// The first missing or invalid input that prevents a price suggestion.
  ///
  /// The AI service needs the five model inputs, and the endpoint is keyed by a
  /// saved draft. Checking both sets here gives the seller one specific message
  /// beside the button instead of silently opening another step.
  String? _suggestionInputError() {
    if (!_catalog.state.isReady) {
      return _catalog.state.hasFailed
          ? 'Livestock types could not be loaded. Retry, then request a price.'
          : 'Livestock types are still loading. Please try again.';
    }

    final LivestockType? type = _selectedType(_catalog.state.types);
    if (type == null) {
      return 'Choose the type of livestock before requesting a price.';
    }
    if (_breed.text.trim().isEmpty) {
      return 'Choose a supported breed before requesting a price.';
    }
    if (_gender == null) {
      return 'Select the animal sex before requesting a price.';
    }
    if (_ageValue.text.trim().isEmpty || _ageUnit == null) {
      return 'Add the animal age and unit before requesting a price.';
    }
    if ((int.tryParse(_ageValue.text.trim()) ?? 0) <= 0) {
      return 'The age must be greater than zero for a price suggestion.';
    }
    final String? ageError = validateAgeValue(_ageValue.text, unit: _ageUnit);
    if (ageError != null) {
      return ageError;
    }
    final String? ageUnitError = validateAgeUnit(_ageUnit);
    if (ageUnitError != null) {
      return ageUnitError;
    }
    if (_weightValue.text.trim().isEmpty || _weightUnit == null) {
      return 'Add the animal weight and unit before requesting a price.';
    }
    if ((double.tryParse(_weightValue.text.trim()) ?? 0) <= 0) {
      return 'The weight must be greater than zero for a price suggestion.';
    }
    final String? weightError = validateWeightValue(_weightValue.text);
    if (weightError != null) {
      return weightError;
    }
    final String? weightUnitError = validateWeightUnit(_weightUnit);
    if (weightUnitError != null) {
      return weightUnitError;
    }

    // The draft has to exist before the endpoint can read it, so the four
    // create-required fields are checked here as well.
    final String? quantityError = validateQuantity(_quantity.text);
    if (quantityError != null) {
      return quantityError;
    }
    final String? priceError = validateAskingPrice(_askingPrice.text);
    if (priceError != null) {
      return priceError;
    }
    final String? locationError = _validateLocation();
    if (locationError != null) {
      return locationError;
    }
    return null;
  }

  /// Clears a result as soon as one of the model inputs changes.
  void _onSuggestionInputChanged() {
    _suggestionInputRevision++;
    _controller.clearPriceSuggestion();
    if (_suggestionInputMessage != null && mounted) {
      setState(() => _suggestionInputMessage = null);
    }
  }

  /// Clears an input message when a draft-only field changes.
  ///
  /// Quantity and asking price are not model inputs, so editing them must not
  /// discard a valid per-head estimate. Only the local pre-check message is
  /// stale.
  void _onSuggestionDraftInputChanged() {
    if (_suggestionInputMessage != null && mounted) {
      setState(() => _suggestionInputMessage = null);
    }
  }

  /// The positive whole-number quantity, or `null` while it is empty/invalid.
  int? get _quantityValue {
    final int? value = int.tryParse(_quantity.text.trim());
    return value != null && value > 0 ? value : null;
  }

  /// The live, informational total for the listing.
  String? get _totalListingValue {
    final int? quantity = _quantityValue;
    final double? unitPrice = AppFormatters.parseDecimal(_askingPrice.text);
    if (quantity == null || unitPrice == null || unitPrice < 0) {
      return null;
    }
    return _formatPeso(unitPrice * quantity);
  }

  /// The typed asking price formatted for display, or `null`.
  String? get _perHeadPriceLabel {
    final double? unitPrice = AppFormatters.parseDecimal(_askingPrice.text);
    if (unitPrice == null || unitPrice < 0) {
      return null;
    }
    return _formatPeso(unitPrice);
  }

  /// Whether the current form can call the draft-only suggestion endpoint.
  bool get _canRequestPriceSuggestion {
    final Listing? target = _saved ?? widget.listing;
    return target == null || target.status == ListingStatus.draft;
  }

  void _useSuggestedPrice(String value) {
    setState(() => _askingPrice.text = value);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Listing? listing = widget.listing;

    if (listing?.inventoryReconciliationRequired ?? false) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit listing')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const NoticeBanner(
                    accent: AppColors.warning,
                    icon: Icons.inventory_2_outlined,
                    message: 'Inventory reconciliation is required before this listing can be edited.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Back to My Listings'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // The server refuses an edit for a listing that is not a `draft` or an
    // `active` one, so the form is not even offered for the other states rather
    // than being shown and then failing on save.
    if (listing != null && !SellerListingController.canEdit(listing)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit listing')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              child: Text(
                'This listing cannot be edited while it is '
                '${listingStatusLabel(listing.status).toLowerCase()}. '
                '${listingStatusExplanation(listing.status)}',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit listing' : 'Create a listing'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? child) {
            final SellerListingState state = _controller.state;
            final bool busy = _submitting || state.isActioning;

            // The approved design: the three steps across the top, the
            // current step's fields below, and Back / Continue pinned to the
            // bottom edge instead of trailing the fields.
            return Column(
              children: <Widget>[
                Expanded(
                  child: ExcludeSemantics(
                    child: Form(
                      key: _formKey,
                      child: Stepper(
                        type: StepperType.horizontal,
                        elevation: 0,
                        margin: EdgeInsets.zero,
                        currentStep: _step,
                        onStepContinue: busy ? null : _onStepContinue,
                        onStepCancel: busy ? null : _onStepCancel,
                        // The actions live in the pinned bar below.
                        controlsBuilder:
                            (BuildContext context, ControlsDetails details) =>
                                const SizedBox.shrink(),
                        steps: <Step>[
                          Step(
                            title: const Text('Information'),
                            isActive: _step >= 0,
                            state: _step > 0
                                ? StepState.complete
                                : StepState.indexed,
                            content: _buildInformationStep(state),
                          ),
                          Step(
                            title: const Text('Details'),
                            isActive: _step >= 1,
                            state: _step > 1
                                ? StepState.complete
                                : (_step == 1
                                      ? StepState.indexed
                                      : StepState.disabled),
                            content: _buildDetailsStep(state),
                          ),
                          Step(
                            title: const Text('Review'),
                            isActive: _step >= 2,
                            state: _step == 2
                                ? StepState.indexed
                                : StepState.disabled,
                            content: _buildReviewStep(state),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _FormActionBar(
                  backKey: _step == 2
                      ? const ValueKey<String>('listing-review-back')
                      : null,
                  // On the first step Back leaves the form, as the close
                  // button does; afterwards it returns to the previous step.
                  onBack: busy
                      ? null
                      : (_step == 0
                            ? () => Navigator.of(context).maybePop()
                            : _onStepCancel),
                  primaryLabel: _step == 2
                      ? (_isEditing ? 'Save changes' : 'Save as draft')
                      : 'Continue',
                  onPrimary: busy
                      ? null
                      : (_step == 2 ? _save : _onStepContinue),
                  busy: busy && _step == 2,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildInformationStep(SellerListingState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Intro(
          isEditing: _isEditing,
          actionMessage: state.actionMessage,
          actionError: state.actionErrorMessage,
          conflictMessage: state.conflictMessage,
          serverErrors: state.validationErrors,
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'What is being sold',
          children: <Widget>[
            ListenableBuilder(
              listenable: _catalog,
              builder: (BuildContext context, Widget? child) {
                final LivestockTypesState catalogState = _catalog.state;
                if (catalogState.isReady) {
                  final LivestockType? selectedType = _selectedType(
                    catalogState.types,
                  );
                  final String? selected = selectedType?.value;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _Dropdown<String>(
                        label: 'Type of livestock',
                        value: selected,
                        items: catalogState.types
                            .map(
                              (LivestockType type) => DropdownMenuItem<String>(
                                value: type.value,
                                child: Text(type.label),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (String? value) =>
                            _selectLivestockType(value, catalogState.types),
                        validator: validateLivestockType,
                        serverErrors: state.validationErrors['livestock_type'],
                      ),
                      if (_livestockType != null &&
                          selected == null) ...<Widget>[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'This listing has an unsupported legacy type. Choose a supported type before saving.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ],
                    ],
                  );
                }

                if (catalogState.hasFailed) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        catalogState.errorMessage ??
                            'Could not load livestock types.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      TextButton(
                        onPressed: _catalog.retry,
                        child: const Text('Retry'),
                      ),
                    ],
                  );
                }

                return const InputDecorator(
                  decoration: InputDecoration(
                    label: FieldLabel('Type of livestock'),
                  ),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: AppSpacing.sm),
                      Text('Loading livestock types...'),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            ListenableBuilder(
              listenable: _catalog,
              builder: (BuildContext context, Widget? child) {
                final LivestockTypesState catalogState = _catalog.state;
                LivestockType? type;
                for (final LivestockType item in catalogState.types) {
                  if (item.value == _livestockType) {
                    type = item;
                    break;
                  }
                }
                final List<String> breeds = type == null
                    ? const <String>[]
                    : _breedOptions(type);

                return _Dropdown<String>(
                  key: ValueKey<String>(
                    'listing-breed-${type?.value ?? 'none'}',
                  ),
                  label: 'Breed (optional)',
                  value: breeds.contains(_breed.text) ? _breed.text : '',
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('No breed selected'),
                    ),
                    ...breeds.map(
                      (String breed) => DropdownMenuItem<String>(
                        value: breed,
                        child: Text(breed),
                      ),
                    ),
                  ],
                  onChanged: type == null
                      ? null
                      : (String? value) => setState(() {
                          _clearBreed =
                              _isEditing &&
                              _breed.text.isNotEmpty &&
                              (value == null || value.isEmpty);
                          _breed.text = value ?? '';
                        }),
                  validator: validateBreed,
                  serverErrors: state.validationErrors['breed'],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _TextField(
                    controller: _ageValue,
                    formFieldKey: _ageValueFieldKey,
                    label: 'Age',
                    hint: 'e.g. 18',
                    helper:
                        'Required. Per animal, not the combined age of the group.',
                    validator: (String? value) =>
                        _legacyAgeIncomplete && (value ?? '').trim().isEmpty
                        ? null
                        : validateAgeValue(value, unit: _ageUnit),
                    serverErrors: state.validationErrors['age_value'],
                    keyboardType: TextInputType.number,
                    inputFormatters: const <TextInputFormatter>[
                      DigitsOnlyInputFormatter(),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _Dropdown<String>(
                    label: 'Age unit',
                    value: _ageUnit,
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(
                        value: 'day',
                        child: Text('Day'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'month',
                        child: Text('Month'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'year',
                        child: Text('Year'),
                      ),
                    ],
                    onChanged: (String? value) {
                      setState(() => _ageUnit = value);
                      // The limit is per unit, so the age the seller already
                      // typed may now be out of range. Only that field is
                      // re-validated; no untouched field gains an error.
                      _ageValueFieldKey.currentState?.validate();
                      _onSuggestionInputChanged();
                    },
                    validator: (String? value) =>
                        state.validationErrors['age_unit']?.first ??
                        (_legacyAgeIncomplete && _ageValue.text.trim().isEmpty
                            ? null
                            : validateAgeUnit(value)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _Dropdown<String>(
              label: 'Age Information',
              value: _ageInformation,
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: 'known', child: Text('Known')),
                DropdownMenuItem<String>(
                  value: 'estimated',
                  child: Text('Estimated'),
                ),
              ],
              onChanged: (String? value) {
                if (value == null) {
                  return;
                }
                setState(() => _ageInformation = value);
                _onSuggestionInputChanged();
              },
              validator: (String? value) => value == null || value.isEmpty
                  ? 'Choose the age information.'
                  : null,
              serverErrors: state.validationErrors['age_information'],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Estimated is allowed when the exact age is unavailable. Buyers '
              'will see it as an estimate.',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _TextField(
                    controller: _weightValue,
                    label: 'Weight',
                    hint: 'e.g. 320',
                    helper:
                        'Required. Per animal, not the combined weight of the group.',
                    validator: (String? value) =>
                        _legacyWeightIncomplete && (value ?? '').trim().isEmpty
                        ? null
                        : validateWeightValue(value),
                    serverErrors: state.validationErrors['weight_value'],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: const <TextInputFormatter>[
                      DecimalInputFormatter(),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _Dropdown<String>(
                    label: 'Weight unit',
                    value: _weightUnit,
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(
                        value: 'kg',
                        child: Text('Kilograms'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'lb',
                        child: Text('Pounds'),
                      ),
                    ],
                    onChanged: (String? value) {
                      setState(() => _weightUnit = value);
                      _onSuggestionInputChanged();
                    },
                    validator: (String? value) =>
                        state.validationErrors['weight_unit']?.first ??
                        (_legacyWeightIncomplete &&
                                _weightValue.text.trim().isEmpty
                            ? null
                            : validateWeightUnit(value)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _Dropdown<String>(
              label: 'Weight Information',
              value: _weightInformation,
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                  value: 'measured',
                  child: Text('Measured'),
                ),
                DropdownMenuItem<String>(
                  value: 'estimated',
                  child: Text('Estimated'),
                ),
              ],
              onChanged: (String? value) {
                if (value == null) {
                  return;
                }
                setState(() => _weightInformation = value);
                _onSuggestionInputChanged();
              },
              validator: (String? value) => value == null || value.isEmpty
                  ? 'Choose the weight information.'
                  : null,
              serverErrors: state.validationErrors['weight_information'],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Estimated is allowed when the exact weight is unavailable. '
              'Buyers will see it as an estimate.',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(title: 'Photos', children: <Widget>[ListingPhotoGrid()]),
      ],
    );
  }

  Widget _buildDetailsStep(SellerListingState state) {
    final bool busy = _submitting || state.isActioning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionCard(
          title: 'Availability and price',
          children: <Widget>[
            _TextField(
              controller: _quantity,
              label: 'Total Animals in This Listing',
              hint: 'e.g. 12',
              helper:
                  'Required. This is the full listing quantity, including '
                  'animals already reserved or sold. Animals grouped in one listing must have similar '
                  'characteristics and share one price per head. List '
                  'significantly different animals separately.',
              helperMaxLines: 4,
              validator: validateQuantity,
              serverErrors: state.validationErrors['total_quantity'] ??
                  state.validationErrors['quantity'],
              keyboardType: TextInputType.number,
              inputFormatters: const <TextInputFormatter>[
                DigitsOnlyInputFormatter(),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _TextField(
              controller: _askingPrice,
              label: 'Asking Price (₱) — Per Head',
              hint: 'e.g. 42500',
              helper:
                  'Required. Price for one animal. The total listing value is '
                  'quantity × this price.',
              validator: validateAskingPrice,
              serverErrors: state.validationErrors['asking_price'],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const <TextInputFormatter>[
                DecimalInputFormatter(),
              ],
              prefixText: '₱ ',
            ),
            const SizedBox(height: AppSpacing.xs),
            ListenableBuilder(
              listenable: Listenable.merge(<Listenable>[
                _quantity,
                _askingPrice,
              ]),
              builder: (BuildContext context, Widget? child) {
                final int? quantity = _quantityValue;
                final String? total = _totalListingValue;
                final String? unitPrice = _perHeadPriceLabel;
                if (quantity == null || total == null || unitPrice == null) {
                  return const SizedBox.shrink();
                }
                return Text(
                  'Total listing value: $total '
                  '($quantity × $unitPrice per head; informational only).',
                  key: const ValueKey<String>('total-listing-value'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                );
              },
            ),
            if (_canRequestPriceSuggestion) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                key: const ValueKey<String>('ai-suggest-price'),
                onPressed: busy ? null : _suggestPrice,
                icon: state.action == SellerListingAction.suggestingPrice
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: const Text('AI Suggest Price'),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'AI uses type, breed, sex, age, and weight. Requesting AI saves '
                'this draft first. The suggestion is a per-head reference only; '
                'you still choose the final asking price.',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              if (_suggestionInputMessage != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                NoticeBanner(
                  accent: AppColors.warning,
                  icon: Icons.info_outline,
                  message: _suggestionInputMessage!,
                  backgroundColor: AppColors.warningSurface,
                ),
              ],
              if (state.priceSuggestion != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                ListenableBuilder(
                  listenable: _quantity,
                  builder: (BuildContext context, Widget? child) =>
                      _AiPriceSuggestionPanel(
                        result: state.priceSuggestion!,
                        quantity: _quantityValue,
                        measurementsEstimated:
                            _ageInformation == 'estimated' ||
                            _weightInformation == 'estimated',
                        onUsePrice: _useSuggestedPrice,
                        onRetry: busy ? null : _suggestPrice,
                      ),
                ),
              ],
            ],
            const SizedBox(height: AppSpacing.md),
            TrinidadLocationSelector(
              value: _selectedLocation,
              legacyAddress: _legacyLocation,
              maxFormattedLength: TrinidadLocation.listingLocationMax,
              isRequired:
                  !_isEditing ||
                  _locationWasTouched ||
                  _selectedLocation != null ||
                  _initialLocation.isEmpty,
              enabled: !_submitting && !state.isActioning,
              externalError: state.validationErrors['location']?.first,
              onChanged: _handleLocationChanged,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'Details',
          children: <Widget>[
            _Dropdown<String>(
              label: 'Gender',
              value: _gender,
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: 'male', child: Text('Male')),
                DropdownMenuItem<String>(
                  value: 'female',
                  child: Text('Female'),
                ),
              ],
              onChanged: (String? value) {
                setState(() => _gender = value);
                _onSuggestionInputChanged();
              },
              serverErrors: state.validationErrors['gender'],
            ),
            const SizedBox(height: AppSpacing.md),
            _TextField(
              controller: _healthStatus,
              label: 'Health status',
              hint: 'e.g. Healthy, vaccinated',
              validator: validateOptionalShortText,
              serverErrors: state.validationErrors['health_status'],
            ),
            const SizedBox(height: AppSpacing.md),
            _TextField(
              controller: _vaccination,
              label: 'Vaccination record',
              hint: 'e.g. Bovi-Shield given March',
              validator: validateOptionalShortText,
              serverErrors: state.validationErrors['vaccination'],
            ),
            const SizedBox(height: AppSpacing.md),
            _TextField(
              controller: _shortDescription,
              label: 'Short description',
              hint: 'One or two lines about the livestock.',
              validator: validateOptionalShortText,
              serverErrors: state.validationErrors['short_description'],
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.md),
            _TextField(
              controller: _additionalNotes,
              label: 'Additional notes',
              hint: 'Anything a buyer should know.',
              validator: validateAdditionalNotes,
              serverErrors: state.validationErrors['additional_notes'],
              maxLines: 4,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReviewStep(SellerListingState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Intro(
          isEditing: _isEditing,
          actionMessage: state.actionMessage,
          actionError: state.actionErrorMessage,
          conflictMessage: state.conflictMessage,
          serverErrors: state.validationErrors,
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'Summary',
          children: <Widget>[
            _ReviewRow(
              label: 'Type',
              value: _livestockType == null
                  ? '—'
                  : _catalog.state.labelFor(_livestockType!),
            ),
            if (_breed.text.isNotEmpty)
              _ReviewRow(label: 'Breed', value: _breed.text),
            if (_ageValue.text.isNotEmpty && _ageUnit != null)
              _ReviewRow(
                label: _ageInformation == 'estimated'
                    ? 'Estimated Age'
                    : 'Known Age',
                value: '${_ageValue.text} ${_ageUnit!}',
              ),
            if (_gender != null) _ReviewRow(label: 'Gender', value: _gender!),
            if (_weightValue.text.isNotEmpty && _weightUnit != null)
              _ReviewRow(
                label: _weightInformation == 'estimated'
                    ? 'Estimated Weight'
                    : 'Measured Weight',
                value: '${_weightValue.text} ${_weightUnit!}',
              ),
            _ReviewRow(
              label: 'Number of Animals Available',
              value: _quantity.text,
            ),
            _ReviewRow(
              label: 'Asking Price (₱) — Per Head',
              value: '₱ ${_askingPrice.text}',
            ),
            if (_totalListingValue != null)
              _ReviewRow(
                label: 'Total listing value',
                value: '${_totalListingValue!} (informational only)',
              ),
            _ReviewRow(
              label: 'Location',
              value: _locationForSave().trim().isEmpty
                  ? '—'
                  : _locationForSave(),
            ),
            if (_healthStatus.text.isNotEmpty)
              _ReviewRow(label: 'Health', value: _healthStatus.text),
            if (_vaccination.text.isNotEmpty)
              _ReviewRow(label: 'Vaccination', value: _vaccination.text),
            if (_shortDescription.text.isNotEmpty)
              _ReviewRow(label: 'Description', value: _shortDescription.text),
            if (_additionalNotes.text.isNotEmpty)
              _ReviewRow(label: 'Notes', value: _additionalNotes.text),
          ],
        ),
        if ((_legacyAgeIncomplete && _ageValue.text.trim().isEmpty) ||
            (_legacyWeightIncomplete && _weightValue.text.trim().isEmpty)) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'This legacy draft is missing age or weight. You can save it, but '
            'add both before submitting it for review.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.warning),
            textAlign: TextAlign.center,
          ),
        ],
        if (_ageInformation == 'estimated' ||
            _weightInformation == 'estimated') ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Estimated age or weight will be shown to buyers as '
            'seller-provided and not independently verified.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          _isEditing
              ? 'Saving keeps this listing in its current status.'
              : 'Saved as a draft. Only you can see it until you submit it for '
                    'review.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// The result of one AI price-suggestion attempt.
///
/// A successful estimate is the only branch that renders a number. Refusals and
/// failures render a friendly explanation instead, never a placeholder price or
/// an invented confidence score. Raw provider text stays behind Technical
/// details.
class _AiPriceSuggestionPanel extends StatelessWidget {
  const _AiPriceSuggestionPanel({
    required this.result,
    required this.onUsePrice,
    this.quantity,
    this.measurementsEstimated = false,
    this.onRetry,
  });

  final PriceSuggestionResult result;
  final int? quantity;
  final bool measurementsEstimated;
  final ValueChanged<String> onUsePrice;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (!result.hasEstimate) {
      return _SuggestionProblem(
        result: result,
        onRetry: result.canRetry ? onRetry : null,
      );
    }

    final AiPriceEstimate estimate = result.estimate!;
    final String money =
        AppFormatters.formatMoney(estimate.estimatedValue) ??
        estimate.estimatedValue;
    final String? inputSummary = _suggestionInputSummary(
      estimate.inputSnapshot,
    );
    final int? count = quantity;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.auto_awesome,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'AI Suggested Price per Head',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                estimate.isWarning
                    ? 'Review recommended'
                    : 'Within model range',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: estimate.isWarning
                      ? AppColors.warning
                      : AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            money,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'per head',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (count != null && count > 1) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'For $count animals: ${_estimatedTotal(estimate, count)} total '
              '(reference only).',
              key: const ValueKey<String>('ai-estimated-total'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Synthetic Data — Reference Only. This is not a valuation; you '
            'decide the final asking price.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (measurementsEstimated) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Prediction reliability depends on the seller-provided age and '
              'weight estimates.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.warning,
              ),
            ),
          ],
          if (inputSummary != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Based on: $inputSummary',
              key: const ValueKey<String>('ai-input-summary'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            [
              if (estimate.modelVersion != null)
                'Model ${estimate.modelVersion}',
              if (estimate.provenance != null) '${estimate.provenance} data',
            ].join(' · '),
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (estimate.isWarning) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            NoticeBanner(
              accent: AppColors.warning,
              icon: Icons.info_outline,
              message: _friendlyWarningMessage(estimate),
              backgroundColor: AppColors.warningSurface,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => onUsePrice(estimate.estimatedValue),
            icon: const Icon(Icons.edit_outlined, size: 17),
            label: const Text('Use per-head price'),
          ),
          _TechnicalDetails(
            warnings: estimate.warnings,
            reasonCodes: estimate.reasonCodes,
          ),
        ],
      ),
    );
  }
}

/// A refusal or failure: no number, a friendly explanation, and a retry only
/// when a retry could actually change the answer.
class _SuggestionProblem extends StatelessWidget {
  const _SuggestionProblem({required this.result, this.onRetry});

  final PriceSuggestionResult result;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final bool isError =
        result.outcome == PriceSuggestionOutcome.error ||
        result.outcome == PriceSuggestionOutcome.unavailable;
    final String title = switch (result.outcome) {
      PriceSuggestionOutcome.withheld => 'Price suggestion withheld',
      PriceSuggestionOutcome.unavailable => 'Price suggestion unavailable',
      PriceSuggestionOutcome.invalid => 'Cannot generate a price suggestion',
      _ => 'Price suggestion failed',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NoticeBanner(
          accent: isError ? AppColors.error : AppColors.warning,
          icon: isError ? Icons.error_outline : Icons.info_outline,
          title: title,
          message: _friendlyProblemMessage(result),
          backgroundColor: isError
              ? AppColors.error.withValues(alpha: 0.06)
              : AppColors.warningSurface,
        ),
        if (onRetry != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ),
        _TechnicalDetails(
          warnings: result.warnings,
          reasonCodes: result.reasonCodes,
        ),
      ],
    );
  }
}

/// Raw provider warnings and reason codes, kept out of the primary message.
class _TechnicalDetails extends StatelessWidget {
  const _TechnicalDetails({
    this.warnings = const <String>[],
    this.reasonCodes = const <String>[],
  });

  final List<String> warnings;
  final List<String> reasonCodes;

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty && reasonCodes.isEmpty) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: Material(
        type: MaterialType.transparency,
        child: ExpansionTile(
          key: const ValueKey<String>('ai-technical-details'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: AppSpacing.xs),
          title: Text(
            'Technical details',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          children: <Widget>[
            if (warnings.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  warnings.join('\n'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            if (reasonCodes.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Reason codes: ${reasonCodes.join(', ')}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Formats a per-head estimate multiplied by a quantity, for display only.
String _estimatedTotal(AiPriceEstimate estimate, int quantity) {
  final double? value = AppFormatters.parseDecimal(estimate.estimatedValue);
  if (value == null) {
    return estimate.estimatedValue;
  }
  return _formatPeso(value * quantity);
}

/// A seller-facing warning summary that does not restate model thresholds.
String _friendlyWarningMessage(AiPriceEstimate estimate) {
  final bool typical = estimate.reasonCodes.any(
    (String code) =>
        code.startsWith('outside_typical') ||
        code == 'outside_typical_age_weight',
  );
  if (typical) {
    return "The estimate is usable, but the details are outside the model's "
        'usual range. Check the age and weight before using it.';
  }
  return 'The estimate is usable, but the model flagged the input. Review the '
      'details before using it.';
}

/// A seller-facing refusal summary, mapped from stable reason codes.
String _friendlyProblemMessage(PriceSuggestionResult result) {
  final List<String> codes = result.reasonCodes;
  bool has(String prefix) =>
      codes.any((String code) => code.startsWith(prefix));

  switch (result.outcome) {
    case PriceSuggestionOutcome.withheld:
      if (has('outside_supported') ||
          codes.contains('insufficient_model_support')) {
        return 'The prototype model was trained on a limited synthetic range '
            'and cannot estimate this animal. Your listing is still valid and '
            'can be saved. Check the age and weight if they were entered '
            'incorrectly, or continue without a suggestion.';
      }
      if (codes.contains('missing_safety_profile') ||
          codes.contains('model_unavailable')) {
        return 'The price suggestion model is not available right now. You can '
            'continue without a suggestion or try again later.';
      }
      return 'The prototype model cannot estimate this animal from the details '
          'provided. Your listing is still valid and can be saved.';
    case PriceSuggestionOutcome.invalid:
      if (codes.contains('unsupported_breed')) {
        return 'This breed is not covered by the prototype model. Choose a '
            'supported breed or save your listing without a suggestion.';
      }
      if (codes.contains('unsupported_livestock_type')) {
        return 'This livestock type is not covered by the prototype model. '
            'Choose a supported type or save without a suggestion.';
      }
      if (codes.contains('listing_not_draft')) {
        return 'This listing is no longer a draft, so AI suggestions are '
            'unavailable.';
      }
      if (has('missing_') || codes.contains('invalid_measurement')) {
        return 'Add the animal sex, age, and weight before requesting a '
            'suggestion.';
      }
      if (has('invalid_') || has('unsupported_')) {
        return 'The animal details cannot be used for a price suggestion. Check '
            'the age, weight, sex, and breed, then try again.';
      }
      return 'The animal details cannot be used for a price suggestion. Check '
          'the details and try again.';
    case PriceSuggestionOutcome.unavailable:
      return 'The price suggestion service is unavailable right now. You can '
          'continue without a suggestion or try again.';
    case PriceSuggestionOutcome.error:
      return 'The price suggestion could not be generated. You can continue '
          'without a suggestion or try again.';
    case PriceSuggestionOutcome.ok:
    case PriceSuggestionOutcome.warning:
      return result.displayMessage;
  }
}

/// The model input summary, preferring the seller's original units when the
/// server captured them.
String? _suggestionInputSummary(Map<String, dynamic> snapshot) {
  final List<String> parts = <String>[];
  final Object? type = snapshot['livestock_type'];
  if (type is String && type.trim().isNotEmpty) {
    parts.add(_humanizeLabel(type));
  }

  final Object? source = snapshot['source'];
  if (source is Map) {
    final Object? breed = source['breed_raw'];
    if (breed is String && breed.trim().isNotEmpty) {
      parts.add(breed.trim());
    }
  } else {
    final Object? breed = snapshot['breed'];
    if (breed is String && breed.trim().isNotEmpty) {
      parts.add(_humanizeLabel(breed));
    }
  }

  final Object? sex = snapshot['sex'];
  if (sex is String && sex.trim().isNotEmpty) {
    parts.add(_humanizeLabel(sex));
  }

  if (source is Map) {
    final Object? ageValue = source['age_value'];
    final Object? ageUnit = source['age_unit'];
    if (ageValue != null && ageUnit is String) {
      parts.add('$ageValue $ageUnit');
    }
    final Object? weightValue = source['weight_value'];
    final Object? weightUnit = source['weight_unit'];
    if (weightValue != null && weightUnit is String) {
      parts.add('$weightValue $weightUnit');
    }
  } else {
    final Object? ageMonths = snapshot['age_months'];
    if (ageMonths is num) {
      parts.add('${_trimNumber(ageMonths)} months');
    }
    final Object? weightKg = snapshot['weight_kg'];
    if (weightKg is num) {
      parts.add('${_trimNumber(weightKg)} kg');
    }
  }

  return parts.isEmpty ? null : parts.join(' · ');
}

String _humanizeLabel(String value) {
  final String trimmed = value.trim().replaceAll('_', ' ');
  if (trimmed.isEmpty) {
    return trimmed;
  }
  return trimmed
      .split(RegExp(r'\s+'))
      .map(
        (String word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String _trimNumber(num value) => value.toStringAsFixed(value % 1 == 0 ? 0 : 2);

String _formatPeso(double value) {
  final String raw = value.toStringAsFixed(2);
  return AppFormatters.formatMoney(raw) ?? raw;
}

/// What the seller is about to do, stated before the fields.
/// Back and the step's main action, pinned to the bottom of the form.
class _FormActionBar extends StatelessWidget {
  const _FormActionBar({
    required this.backKey,
    required this.onBack,
    required this.primaryLabel,
    required this.onPrimary,
    required this.busy,
  });

  /// Identifies the Back button on the review step.
  final Key? backKey;
  final VoidCallback? onBack;
  final String primaryLabel;
  final VoidCallback? onPrimary;

  /// Shows a spinner in place of the main action's label.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton(
              key: backKey,
              onPressed: onBack,
              child: const Text('Back'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: FilledButton(
              onPressed: onPrimary,
              child: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(primaryLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({
    required this.isEditing,
    required this.actionMessage,
    required this.actionError,
    required this.conflictMessage,
    required this.serverErrors,
  });

  final bool isEditing;
  final String? actionMessage;
  final String? actionError;
  final String? conflictMessage;
  final Map<String, List<String>> serverErrors;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          isEditing ? 'Update your listing' : 'Create a listing',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          isEditing
              ? 'Change any detail. Fields you leave empty stay as they are.'
              : 'A new listing is saved as a draft. You can edit it, and submit '
                    'it for review, before anyone else sees it.',
          style: theme.textTheme.bodySmall,
        ),
        if (conflictMessage != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          ListingConflictNotice(message: conflictMessage!),
        ],
        if (actionError != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          ListingActionErrorBanner(message: actionError!),
        ],
        if (actionMessage != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Text(
            actionMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.success,
            ),
          ),
        ],
        if (serverErrors.isNotEmpty &&
            actionError == null &&
            conflictMessage == null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          ListingActionErrorBanner(
            message: serverErrors.values.expand((List<String> e) => e).first,
          ),
        ],
      ],
    );
  }
}

/// A labelled text field, with a helper line and both error sources merged.
///
/// A `422` and a local check can both be about the same field, and the seller
/// cannot act on two messages stacked on one input. The server's message wins:
/// it is the authority, and a rule it applies that this client does not know
/// about must still be visible.
class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.helperMaxLines = 2,
    this.validator,
    this.serverErrors,
    this.keyboardType,
    this.prefixText,
    this.inputFormatters,
    this.formFieldKey,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helper;
  final int helperMaxLines;
  final String? Function(String?)? validator;
  final List<String>? serverErrors;
  final TextInputType? keyboardType;
  final String? prefixText;

  /// Listing-specific input restrictions, e.g. digits only for the age.
  final List<TextInputFormatter>? inputFormatters;

  /// The key of the field's own [FormFieldState], for the rare case that
  /// re-validating one field is the right thing to do (the age unit changes the
  /// age limit without changing the age).
  final GlobalKey<FormFieldState<String>>? formFieldKey;

  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: formFieldKey,
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      inputFormatters: inputFormatters,
      // Per field, never on the `Form`: a change in one step must not draw
      // errors on fields the seller has not reached yet.
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        label: FieldLabel(label),
        hintText: hint,
        // A prefix is a hint about units, not a separate control, so it is part
        // of the field rather than a separate label the screen reader has to
        // stitch together.
        prefixText: prefixText,
        helperText: helper,
        helperMaxLines: helperMaxLines,
        errorMaxLines: 3,
      ),
      validator: (String? value) =>
          serverErrors?.first ?? validator?.call(value),
    );
  }
}

/// A labelled dropdown.
///
/// Takes a [validator] rather than a pre-computed [errorText], and folds the
/// server's message in through [forceErrorText] on the decoration, because a
/// `DropdownButtonFormField` has no `errorText` parameter of its own and there is
/// nowhere else to put an error for it. The consequence worth stating: a
/// dropdown's error only appears once the form has been validated, the same as
/// every other field here.
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
    this.serverErrors,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  /// A local check, e.g. a unit that is required because a value was entered.
  final FormFieldValidator<T>? validator;

  final List<String>? serverErrors;

  @override
  Widget build(BuildContext context) {
    final String? serverError = serverErrors?.first;

    return DropdownButtonFormField<T>(
      icon: const FieldDropdownIcon(),
      initialValue: value,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      // Per field, like the text inputs. A dropdown the seller has not opened
      // does not show an error because of something typed elsewhere.
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        label: FieldLabel(label),
        errorMaxLines: 3,
        // Through the decoration rather than `forceErrorText`, and deliberately
        // so: `forceErrorText` marks the field *invalid*, which would make
        // `Form.validate()` refuse the next save and so leave the seller with a
        // form that cannot be submitted at all until the stale message is gone.
        // `errorText` is presentation only and blocks nothing.
        errorText: serverError,
      ),
      validator: validator,
    );
  }
}

/// A read-only label-value pair for the review step.
class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
