import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/listing.dart';
import '../state/listing_photo_item.dart';
import '../state/seller_listing_controller.dart';
import '../state/seller_listing_draft.dart';
import '../state/seller_listing_scope.dart';
import '../state/seller_listing_state.dart';
import '../widgets/listing_photo_grid.dart';
import 'seller_listing_input_formatters.dart';
import 'seller_listing_views.dart';
import 'seller_listing_validators.dart';
import '../../../widgets/section_card.dart';

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
  final TextEditingController _livestockType = TextEditingController();
  final TextEditingController _breed = TextEditingController();
  final TextEditingController _ageValue = TextEditingController();
  final TextEditingController _weightValue = TextEditingController();
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _askingPrice = TextEditingController();
  final TextEditingController _location = TextEditingController();
  final TextEditingController _healthStatus = TextEditingController();
  final TextEditingController _vaccination = TextEditingController();
  final TextEditingController _shortDescription = TextEditingController();
  final TextEditingController _additionalNotes = TextEditingController();

  String? _ageUnit;
  String? _gender;
  String? _weightUnit;

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

  /// The listing this form created, if a save succeeded but photo work did not.
  ///
  /// The form stays open on an upload failure so the seller can retry. The next
  /// save must therefore update this record rather than create a second draft.
  Listing? _saved;

  bool get _isEditing => widget.listing != null;

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

    final Listing? listing = widget.listing;
    if (listing != null) {
      final SellerListingDraft draft = SellerListingDraft.fromListing(listing);
      _livestockType.text = draft.livestockType;
      _breed.text = draft.breed;
      _ageValue.text = draft.ageValue;
      _ageUnit = draft.ageUnit;
      _gender = draft.gender;
      _weightValue.text = draft.weightValue;
      _weightUnit = draft.weightUnit;
      _quantity.text = draft.quantity;
      _askingPrice.text = draft.askingPrice;
      _location.text = draft.location;
      _healthStatus.text = draft.healthStatus;
      _vaccination.text = draft.vaccination;
      _shortDescription.text = draft.shortDescription;
      _additionalNotes.text = draft.additionalNotes;
    }

    // Seed the photo composer from the server-served URLs when editing, or
    // leave it empty for a new draft. Photos upload once the listing exists.
    //
    // Deferred to a post-frame callback: startPhotoComposer notifies the
    // controller's listeners, and notifying during this build (initState)
    // throws "setState() or markNeedsBuild() called during build".
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.startPhotoComposer(
        widget.listing?.id,
        widget.listing?.photos ?? const <String>[],
      );
    });
  }

  @override
  void dispose() {
    _livestockType.dispose();
    _breed.dispose();
    _ageValue.dispose();
    _weightValue.dispose();
    _quantity.dispose();
    _askingPrice.dispose();
    _location.dispose();
    _healthStatus.dispose();
    _vaccination.dispose();
    _shortDescription.dispose();
    _additionalNotes.dispose();
    super.dispose();
  }

  SellerListingDraft _buildDraft() => SellerListingDraft(
    livestockType: _livestockType.text,
    breed: _breed.text,
    ageValue: _ageValue.text,
    ageUnit: _ageUnit,
    gender: _gender,
    weightValue: _weightValue.text,
    weightUnit: _weightUnit,
    quantity: _quantity.text,
    askingPrice: _askingPrice.text,
    location: _location.text,
    healthStatus: _healthStatus.text,
    vaccination: _vaccination.text,
    shortDescription: _shortDescription.text,
    additionalNotes: _additionalNotes.text,
  );

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
          validateLivestockType(_livestockType.text),
          validateBreed(_breed.text),
          validateAgeValue(_ageValue.text, unit: _ageUnit),
          validateAgeUnit(_ageUnit, hasValue: _ageValue.text.trim().isNotEmpty),
          validateWeightValue(_weightValue.text),
          validateWeightUnit(
            _weightUnit,
            hasValue: _weightValue.text.trim().isNotEmpty,
          ),
        ];
      case 1:
        return <String?>[
          validateQuantity(_quantity.text),
          validateAskingPrice(_askingPrice.text),
          validateListingLocation(_location.text),
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
    final int? invalidStep = _firstInvalidStep();
    if (invalidStep != null) {
      setState(() => _step = invalidStep);
      // Validated after the frame that opened the bad step, so the messages are
      // painted on the fields the seller is now looking at.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _formKey.currentState?.validate();
      });
      return;
    }

    final SellerListingDraft draft = _buildDraft();
    final Listing? target = _saved ?? widget.listing;

    setState(() => _submitting = true);
    _controller.clearActionMessage();

    final Listing? saved = target != null
        ? await _controller.update(target.id, draft)
        : await _controller.create(draft);

    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);

    if (saved != null) {
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
      return;
    }

    // A `422` arrives as per-field messages. Re-validating after this frame
    // folds the server's message into the field it names (the field validator
    // gives the server precedence), and the step that owns the first one is
    // opened so the message is not hidden behind a Stepper tab.
    final Map<String, List<String>> serverErrors =
        _controller.state.validationErrors;
    if (serverErrors.isEmpty) {
      return;
    }
    final int? errorStep = _firstStepWithServerError(serverErrors);
    if (errorStep != null && errorStep != _step) {
      setState(() => _step = errorStep);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _formKey.currentState?.validate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Listing? listing = widget.listing;

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

            return ExcludeSemantics(
              child: Form(
                key: _formKey,
                child: Stepper(
                  currentStep: _step,
                  onStepContinue: busy ? null : _onStepContinue,
                  onStepCancel: busy ? null : _onStepCancel,
                  controlsBuilder: (BuildContext context, ControlsDetails details) {
                    if (_step == 2) {
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: FilledButton(
                          onPressed: busy ? null : _save,
                          child: busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isEditing ? 'Save changes' : 'Save as draft',
                                ),
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      // Expanded buttons: the test viewport (and small phones)
                      // are narrower than the two buttons' intrinsic widths, so
                      // an unconstrained Row overflows and fails layout. Sharing
                      // the width keeps both actions on one line at any width.
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: FilledButton(
                              onPressed: details.onStepContinue,
                              child: const Text('Continue'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: TextButton(
                              onPressed: details.onStepCancel,
                              child: const Text('Back'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  steps: <Step>[
                    Step(
                      title: const Text('Information'),
                      isActive: _step >= 0,
                      state: _step > 0 ? StepState.complete : StepState.indexed,
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
            _TextField(
              controller: _livestockType,
              label: 'Type of livestock',
              hint: 'e.g. Cattle, Goat, Poultry',
              helper: 'Required. As specific as you like.',
              validator: validateLivestockType,
              serverErrors: state.validationErrors['livestock_type'],
            ),
            const SizedBox(height: AppSpacing.md),
            _TextField(
              controller: _breed,
              label: 'Breed',
              hint: 'e.g. Brahman',
              helper: 'Optional. Used as the listing title.',
              validator: validateBreed,
              serverErrors: state.validationErrors['breed'],
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
                    validator: (String? value) =>
                        validateAgeValue(value, unit: _ageUnit),
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
                    },
                    validator: (String? value) =>
                        state.validationErrors['age_unit']?.first ??
                        validateAgeUnit(
                          value,
                          hasValue: _ageValue.text.trim().isNotEmpty,
                        ),
                  ),
                ),
              ],
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
                    validator: validateWeightValue,
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
                    onChanged: (String? value) =>
                        setState(() => _weightUnit = value),
                    validator: (String? value) =>
                        state.validationErrors['weight_unit']?.first ??
                        validateWeightUnit(
                          value,
                          hasValue: _weightValue.text.trim().isNotEmpty,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(title: 'Photos', children: <Widget>[ListingPhotoGrid()]),
      ],
    );
  }

  Widget _buildDetailsStep(SellerListingState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionCard(
          title: 'Availability and price',
          children: <Widget>[
            _TextField(
              controller: _quantity,
              label: 'Quantity available',
              hint: 'e.g. 12',
              helper: 'Required. How many head this listing covers.',
              validator: validateQuantity,
              serverErrors: state.validationErrors['quantity'],
              keyboardType: TextInputType.number,
              inputFormatters: const <TextInputFormatter>[
                DigitsOnlyInputFormatter(),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _TextField(
              controller: _askingPrice,
              label: 'Asking price',
              hint: 'e.g. 42500',
              helper: 'Required. In pesos, for the whole listing.',
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
            const SizedBox(height: AppSpacing.md),
            _TextField(
              controller: _location,
              label: 'Location',
              hint: 'e.g. Mabalacat, Pampanga',
              helper: 'Required. Where the livestock is.',
              validator: validateListingLocation,
              serverErrors: state.validationErrors['location'],
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
              onChanged: (String? value) => setState(() => _gender = value),
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
            _ReviewRow(label: 'Type', value: _livestockType.text),
            if (_breed.text.isNotEmpty)
              _ReviewRow(label: 'Breed', value: _breed.text),
            if (_ageValue.text.isNotEmpty && _ageUnit != null)
              _ReviewRow(label: 'Age', value: '${_ageValue.text} ${_ageUnit!}'),
            if (_gender != null) _ReviewRow(label: 'Gender', value: _gender!),
            if (_weightValue.text.isNotEmpty && _weightUnit != null)
              _ReviewRow(
                label: 'Weight',
                value: '${_weightValue.text} ${_weightUnit!}',
              ),
            _ReviewRow(label: 'Quantity', value: _quantity.text),
            _ReviewRow(label: 'Asking price', value: '₱ ${_askingPrice.text}'),
            _ReviewRow(label: 'Location', value: _location.text),
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

/// What the seller is about to do, stated before the fields.
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
        labelText: label,
        hintText: hint,
        // A prefix is a hint about units, not a separate control, so it is part
        // of the field rather than a separate label the screen reader has to
        // stitch together.
        prefixText: prefixText,
        helperText: helper,
        helperMaxLines: 2,
        errorMaxLines: 3,
        border: const OutlineInputBorder(),
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
      initialValue: value,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      // Per field, like the text inputs. A dropdown the seller has not opened
      // does not show an error because of something typed elsewhere.
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
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
