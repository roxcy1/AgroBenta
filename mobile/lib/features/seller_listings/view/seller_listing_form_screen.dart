import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/listing.dart';
import '../state/listing_photo_item.dart';
import '../state/seller_listing_controller.dart';
import '../state/seller_listing_draft.dart';
import '../state/seller_listing_scope.dart';
import '../state/seller_listing_state.dart';
import '../widgets/listing_photo_grid.dart';
import 'seller_listing_views.dart';
import 'seller_listing_validators.dart';
import '../../../widgets/section_card.dart';

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
/// It also cannot add photos. There is no upload endpoint (D-10 / GAP-06) and no
/// agreed URL scheme, so a photo picker would either send something the server
/// cannot store or invent a storage contract. The field is left out rather than
/// stubbed.
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

  late final SellerListingController _controller;
  bool _submitting = false;

  bool get _isEditing => widget.listing != null;

  void _onStepContinue() {
    if (_step == 0) {
      if (validateLivestockType(_livestockType.text) != null) {
        setState(() {});
        return;
      }
    }
    if (_step == 1) {
      if (validateQuantity(_quantity.text) != null ||
          validateAskingPrice(_askingPrice.text) != null ||
          validateListingLocation(_location.text) != null) {
        setState(() {});
        return;
      }
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

  Future<void> _save() async {
    final SellerListingDraft draft = _buildDraft();
    if (draft.missingRequiredFields.isNotEmpty) {
      setState(() {});
      return;
    }

    setState(() => _submitting = true);
    _controller.clearActionMessage();

    final Listing? saved = _isEditing
        ? await _controller.update(widget.listing!.id, _buildDraft())
        : await _controller.create(_buildDraft());

    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);

    if (saved != null) {
      // Upload any locally-picked photos that were not yet stored. The server
      // returns the whole listing, so the composer is rebuilt from served URLs
      // and client and server agree.
      final bool hasPending = _controller.photos.any(
        (ListingPhotoItem p) => p.status == ListingPhotoStatus.pending,
      );
      if (hasPending) {
        await _controller.uploadComposerPhotos(saved.id);
      }
      // The caller needs the record it just wrote, to open or refresh with.
      if (mounted) Navigator.of(context).pop(saved);
    }
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
                          : Text(_isEditing ? 'Save changes' : 'Save as draft'),
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
                      : (_step == 1 ? StepState.indexed : StepState.disabled),
                  content: _buildDetailsStep(state),
                ),
                Step(
                  title: const Text('Review'),
                  isActive: _step >= 2,
                  state: _step == 2 ? StepState.indexed : StepState.disabled,
                  content: _buildReviewStep(state),
                ),
              ],
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
                    label: 'Age',
                    hint: 'e.g. 18',
                    validator: validateAgeValue,
                    serverErrors: state.validationErrors['age_value'],
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _Dropdown<String>(
                    label: 'Age unit',
                    value: _ageUnit,
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(
                        value: 'month',
                        child: Text('Month'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'year',
                        child: Text('Year'),
                      ),
                    ],
                    onChanged: (String? value) =>
                        setState(() => _ageUnit = value),
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
                        state
                            .validationErrors['weight_unit']
                            ?.first ??
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
        SectionCard(
          title: 'Photos',
          children: <Widget>[
            ListingPhotoGrid(),
          ],
        ),
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
                DropdownMenuItem<String>(
                  value: 'male',
                  child: Text('Male'),
                ),
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
              _ReviewRow(
                label: 'Age',
                value: '${_ageValue.text} ${_ageUnit!}',
              ),
            if (_gender != null)
              _ReviewRow(label: 'Gender', value: _gender!),
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
              _ReviewRow(
                label: 'Description',
                value: _shortDescription.text,
              ),
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
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
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
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

