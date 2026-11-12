import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../widgets/field_label.dart';
import '../../auth/state/auth_controller.dart';
import '../../auth/state/auth_scope.dart';
import '../../../models/seller_verification.dart';
import '../../../models/trinidad_location.dart';
import '../../../models/user.dart';
import '../../../features/profile/state/profile_scope.dart';
import '../../trinidad_location/state/trinidad_location_controller.dart';
import '../../trinidad_location/state/trinidad_location_scope.dart';
import '../../../widgets/detail_row.dart';
import '../../../widgets/section_card.dart';
import '../../../widgets/trinidad_location_selector.dart';
import '../state/seller_verification_controller.dart';
import '../state/seller_verification_documents_controller.dart';
import '../state/seller_verification_documents_state.dart';
import '../state/seller_verification_scope.dart';
import '../state/seller_verification_state.dart';
import '../widgets/seller_verification_document_card.dart';
import '../widgets/seller_verification_farm_photos_card.dart';
import 'seller_verification_documents.dart';
import 'seller_verification_submitted_screen.dart';
import 'seller_verification_validators.dart';
import 'seller_verification_views.dart';

/// The seller application form — `POST /api/seller-verification`.
///
/// A three-step wizard — **Basic Information** → **Documents** → **Review** —
/// over a single route, with the step held in [_step]. The reference shows a
/// fourth "Submitted" step; that terminal state is a separate screen
/// ([SellerVerificationSubmittedScreen]) pushed once the server confirms, so the
/// indicator here never advances past [Review] and "Submitted" is only ever
/// shown after the backend answered (doc 04/05).
///
/// A Flutter [Stepper] is deliberately not used: its vertical body keeps every
/// step mounted through an `AnimatedCrossFade`, so a widget test tapping "Next"
/// would still find the next step's fields on screen and could not tell the steps
/// apart. One index and one visible step at a time is both simpler and testable.
///
/// ## Only supported fields
///
/// The form submits required phone and address snapshots alongside the optional
/// `business_name`, `business_location` and `business_description` fields. Full
/// name is shown read-only from the account ([accountName]) because it comes
/// from `/auth/me`, not the application. The evidence documents are uploaded through
/// `/seller-verification/documents` before submission, because the submit
/// endpoint refuses an application whose required documents are missing (a
/// `422`). The app
/// never sends `role` or `seller_capability`.
///
/// The same screen serves a first application and a resubmission;
/// [isResubmission] only pre-fills the rejected values and seeds the document
/// slots from the record, because a resubmission is a **new** record, never an
/// edit of the rejected one.
class SellerVerificationFormScreen extends StatefulWidget {
  const SellerVerificationFormScreen({
    required this.isResubmission,
    this.accountName,
    this.pickImage,
    super.key,
  });

  /// Whether this is a resubmission after a rejection.
  ///
  /// Affects the prefilled values and the seeded document slots only. It never
  /// changes the request.
  final bool isResubmission;

  /// The account holder's full name, from `/auth/me`, shown read-only.
  ///
  /// Optional so the screen can be mounted without the account (the shell and
  /// some tests do not carry it); the row is simply omitted when it is absent.
  final String? accountName;

  /// Overrides how an image is picked, for tests.
  ///
  /// Production passes nothing and the screen uses [pickVerificationImage]. A
  /// test supplies a function returning an in-memory [XFile] so the flow can be
  /// exercised without a real picker or a camera.
  final Future<XFile?> Function(VerificationDocumentType type)? pickImage;

  @override
  State<SellerVerificationFormScreen> createState() =>
      _SellerVerificationFormScreenState();
}

class _SellerVerificationFormScreenState
    extends State<SellerVerificationFormScreen> {
  /// The steps shown by the indicator. "Submitted" is the terminal step the flow
  /// moves to; it is not edited here, so the indicator never advances past
  /// [Review].
  static const List<String> _steps = <String>[
    'Basic Information',
    'Documents',
    'Review',
    'Submitted',
  ];

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _governmentIdFormKey = GlobalKey<FormState>();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _businessName = TextEditingController();
  final TextEditingController _businessLocation = TextEditingController();
  final TextEditingController _businessDescription = TextEditingController();
  final TextEditingController _governmentIdDescription =
      TextEditingController();

  late final SellerVerificationController _controller;
  late final SellerVerificationDocumentsController _documents;
  late final TrinidadLocationController _locationCatalog;
  AuthController? _authController;
  int? _authenticatedUserId;
  bool _authIdentityInitialized = false;
  bool _phonePrefilled = false;
  bool _addressPrefilled = false;
  String? _pendingAddress;
  TrinidadLocation? _location;
  String? _legacyAddress;
  SellerVerification? _previousVerification;
  GovernmentIdType? _governmentIdType;

  /// Zero-based index of the step being shown.
  int _step = 0;

  /// The field errors currently on screen, so a repeat of the same server error
  /// does not re-validate for nothing.
  Map<String, List<String>> _displayedErrors = const <String, List<String>>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final AuthController? authController = AuthScope.maybeOf(context);
    if (!identical(authController, _authController)) {
      _authController?.removeListener(_handleAuthChanged);
      _authController = authController;
      _authController?.addListener(_handleAuthChanged);
    }
    _syncAuthenticatedUser();
    _prefillContactFields();
  }

  void _handleAuthChanged() => _syncAuthenticatedUser();

  void _syncAuthenticatedUser() {
    final AuthController? authController = _authController;
    final int? userId = authController?.state.isSignedIn == true
        ? authController?.state.user?.id
        : null;

    if (!_authIdentityInitialized) {
      _authenticatedUserId = userId;
      _authIdentityInitialized = true;
      return;
    }

    if (userId != _authenticatedUserId) {
      _authenticatedUserId = userId;
      _documents.resetForAccountChange();
      _previousVerification = null;
      _businessName.clear();
      _businessLocation.clear();
      _businessDescription.clear();
      _governmentIdDescription.clear();
      _governmentIdType = null;
      _phone.text = authController?.state.user?.phone ?? '';
      _queueAddress(
        ProfileScope.maybeReadOf(context)?.state.user?.location ??
            authController?.state.user?.location,
      );
      _phonePrefilled = true;
      _addressPrefilled = true;
    }
  }

  void _prefillContactFields() {
    final User? user = _authController?.state.user;
    if (user == null) {
      return;
    }

    if (!_phonePrefilled) {
      _phone.text = _previousVerification?.phone ?? user.phone ?? '';
      _phonePrefilled = true;
    }
    if (!_addressPrefilled) {
      _queueAddress(
        _previousVerification?.address ??
            ProfileScope.maybeReadOf(context)?.state.user?.location ??
            user.location,
      );
      _addressPrefilled = true;
    }
  }

  void _queueAddress(String? rawAddress) {
    _pendingAddress = rawAddress?.trim();
    _restoreQueuedAddress();
  }

  void _restoreQueuedAddress() {
    final String? rawAddress = _pendingAddress;
    final TrinidadLocationCatalog? catalog = _locationCatalog.state.catalog;
    final TrinidadLocation? parsed = catalog?.parseAddress(rawAddress);
    _location = parsed;
    _legacyAddress =
        rawAddress != null && rawAddress.isNotEmpty && parsed == null
        ? rawAddress
        : null;
  }

  void _handleLocationCatalogChanged() {
    if (_pendingAddress != null && _locationCatalog.state.isReady && mounted) {
      setState(_restoreQueuedAddress);
    }
  }

  void _handleLocationChanged(TrinidadLocation? value) {
    setState(() {
      _location = value;
      _legacyAddress = null;
      _pendingAddress = null;
      _addressPrefilled = true;
    });
  }

  @override
  void initState() {
    super.initState();
    // `readOf`, not `of`: a dependency cannot be registered from `initState`, and
    // the screen rebuilds on every keystroke otherwise.
    _controller = SellerVerificationScope.readOf(context);
    _documents = SellerVerificationDocumentsController(
      SellerVerificationScope.repositoryOf(context),
    );
    _locationCatalog = TrinidadLocationScope.readOf(context);
    _locationCatalog.addListener(_handleLocationCatalogChanged);

    final SellerVerification? previous = _controller.state.verification;
    _previousVerification = previous;

    // A resubmission starts from what was rejected, so the seller corrects the
    // fields that were the problem instead of retyping them. These are the
    // server's own values from the record already on screen — no local copy of
    // the application is kept anywhere.
    if (widget.isResubmission && previous != null) {
      _businessName.text = previous.businessName ?? '';
      _businessLocation.text = previous.businessLocation ?? '';
      _businessDescription.text = previous.businessDescription ?? '';
      _governmentIdType = previous.governmentIdType;
      _governmentIdDescription.text = previous.governmentIdDescription ?? '';
      if (previous.phone != null) {
        _phone.text = previous.phone!;
        _phonePrefilled = true;
      }
      if (previous.address != null) {
        _queueAddress(previous.address);
        _addressPrefilled = true;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _locationCatalog.ensureLoaded();
    });

    // Historical documents remain previewable but are not staged for a new
    // resubmission; the controller seeds them as requiring a fresh upload.
    unawaited(_documents.seedFrom(previous));
  }

  /// A `TextFormField` runs its validator when its value changes and when
  /// `validate()` is called — not when the widget rebuilds. A `422` therefore
  /// arrives after the last validation and would never appear on the field
  /// without this.
  ///
  /// `validate()` is deferred to a post-frame callback because calling it during
  /// a build would re-validate while the tree is being assembled.
  void _revealServerFieldErrors(Map<String, List<String>> errors) {
    if (mapEquals(errors, _displayedErrors)) {
      return;
    }
    _displayedErrors = Map<String, List<String>>.of(errors);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _formKey.currentState?.validate();
        _governmentIdFormKey.currentState?.validate();
      }
    });
  }

  @override
  void dispose() {
    _authController?.removeListener(_handleAuthChanged);
    _businessName.dispose();
    _businessLocation.dispose();
    _businessDescription.dispose();
    _governmentIdDescription.dispose();
    _phone.dispose();
    _documents.dispose();
    _locationCatalog.removeListener(_handleLocationCatalogChanged);
    super.dispose();
  }

  void _goToDocuments() {
    if (_locationCatalog.state.isReady &&
        (_formKey.currentState?.validate() ?? false)) {
      setState(() => _step = 1);
    }
  }

  void _goToReview() {
    final bool idInformationValid =
        _governmentIdFormKey.currentState?.validate() ?? false;
    if (idInformationValid && _documents.state.allRequiredUploaded) {
      setState(() => _step = 2);
    }
  }

  void _goToStep(int step) {
    setState(() => _step = step);
  }

  Future<void> _pick(VerificationDocumentType type) async {
    final Future<XFile?> Function(VerificationDocumentType) picker =
        widget.pickImage ?? pickVerificationImage;
    final XFile? file = await picker(type);
    if (file == null || !mounted) {
      return;
    }
    await _documents.pickAndUpload(type: type, file: file);
  }

  Future<void> _pickFarmPhoto() async {
    final Future<XFile?> Function(VerificationDocumentType) picker =
        widget.pickImage ?? pickVerificationImage;
    final XFile? file = await picker(VerificationDocumentType.farmPhoto);
    if (file == null || !mounted) {
      return;
    }
    await _documents.addFarmPhoto(file);
  }

  Future<void> _chooseAndPickBackImage() async {
    final bool uploadSelected = await _documents.chooseBackImage(
      hasNoBackImage: false,
    );
    if (uploadSelected && mounted) {
      await _pick(VerificationDocumentType.idDocumentBack);
    }
  }

  Future<void> _submit() async {
    final TrinidadLocationCatalog? catalog = _locationCatalog.state.catalog;
    final bool created = await _controller.submit(
      phone: _phone.text.trim(),
      address: catalog == null
          ? ''
          : (_location?.formattedAddress(
                  municipality: catalog.municipality,
                  province: catalog.province,
                ) ??
                ''),
      businessName: _businessName.text,
      businessLocation: _businessLocation.text,
      businessDescription: _businessDescription.text,
      governmentIdType: _governmentIdType?.value ?? '',
      governmentIdDescription: _governmentIdType == GovernmentIdType.others
          ? _governmentIdDescription.text
          : null,
      hasNoBackImage: _documents.state.hasNoBackImage == true,
    );

    if (!mounted) {
      return;
    }

    if (created) {
      // The controller already holds the server's record, so the status screen
      // behind this route is showing it. The confirmation is shown on its own
      // screen rather than popping, so the success is stated only after the
      // backend answered.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              const SellerVerificationSubmittedScreen(),
        ),
      );
      return;
    }

    // Return to the step containing the rejected fields, then validate after
    // that step's form has mounted again.
    if (_controller.state.validationErrors.isNotEmpty) {
      final Set<VerificationDocumentType> documentsNeedingUpload = _controller
          .state
          .validationErrors
          .keys
          .map(
            (String key) => VerificationDocumentType.values.where(
              (VerificationDocumentType type) => type.value == key,
            ),
          )
          .expand((Iterable<VerificationDocumentType> matches) => matches)
          .where(
            (VerificationDocumentType type) =>
                type != VerificationDocumentType.farmPhoto,
          )
          .toSet();
      if (documentsNeedingUpload.isNotEmpty) {
        _documents.markDocumentsForReupload(documentsNeedingUpload);
      }
      final bool governmentIdError =
          _controller.state.validationErrors.containsKey(
            'government_id_type',
          ) ||
          _controller.state.validationErrors.containsKey(
            'government_id_description',
          );
      setState(() {
        // ID metadata and document errors belong on Documents; the contact and
        // business snapshot fields belong on Basic Information.
        _step =
            governmentIdError ||
                _controller.state.validationErrors.keys.any(
                  (String key) => VerificationDocumentType.values.any(
                    (VerificationDocumentType type) => type.value == key,
                  ),
                )
            ? 1
            : 0;
        _displayedErrors = const <String, List<String>>{};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seller Application')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[
            _controller,
            _documents,
            _locationCatalog,
          ]),
          builder: (BuildContext context, Widget? child) {
            final SellerVerificationState state = _controller.state;
            final SellerVerificationDocumentsState documents = _documents.state;
            final bool isSubmitting =
                state.status == SellerVerificationUiStatus.submitting;

            // Must run on every state change, including one that only carries
            // `validationErrors` — see [_revealServerFieldErrors].
            _revealServerFieldErrors(state.validationErrors);

            return ListView(
              // Re-keyed per step so switching steps starts at the top rather
              // than at the scroll offset the previous step was left at.
              key: ValueKey<int>(_step),
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              children: <Widget>[
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        SellerApplicationProgressIndicator(
                          steps: _steps,
                          currentStep: _step,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (state.conflictMessage != null) ...<Widget>[
                          SellerVerificationConflictNotice(
                            message: state.conflictMessage!,
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        if (state.errorMessage != null) ...<Widget>[
                          _FormErrorBanner(message: state.errorMessage!),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        ...switch (_step) {
                          0 => _basicInformation(isSubmitting),
                          1 => _documentsStep(documents, isSubmitting),
                          _ => _review(isSubmitting, documents),
                        },
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

  List<Widget> _basicInformation(bool isSubmitting) {
    final ThemeData theme = Theme.of(context);
    final String? accountName =
        widget.accountName ?? _authController?.state.user?.name;

    return <Widget>[
      Text('Basic Information', style: theme.textTheme.titleLarge),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Provide your basic details as a seller. We use this to verify you '
        'before you start selling.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (accountName != null) ...<Widget>[
              TextFormField(
                initialValue: accountName,
                readOnly: true,
                decoration: const InputDecoration(
                  label: FieldLabel('Full name'),
                  helperText: 'From your account — cannot be changed here.',
                  suffixIcon: FieldIcon(Icon(Icons.lock_outline)),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              maxLength: kSellerVerificationPhoneMax,
              enabled: !isSubmitting,
              decoration: const InputDecoration(
                label: FieldLabel('Phone number'),
                helperText: 'Required for seller verification.',
              ),
              validator: (String? value) =>
                  validateVerificationPhone(value) ??
                  _controller.state.errorFor('phone'),
            ),
            const SizedBox(height: AppSpacing.md),
            TrinidadLocationSelector(
              value: _location,
              legacyAddress: _legacyAddress,
              maxFormattedLength: kSellerVerificationAddressMax,
              isRequired: true,
              enabled: !isSubmitting,
              externalError: _controller.state.errorFor('address'),
              onChanged: _handleLocationChanged,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _businessName,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: kSellerVerificationShortFieldMax,
              enabled: !isSubmitting,
              decoration: const InputDecoration(
                label: FieldLabel('Business name'),
                helperText: 'Optional. Your farm or business name.',
              ),
              validator: (String? value) =>
                  validateBusinessName(value) ??
                  _controller.state.errorFor('business_name'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _businessLocation,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: kSellerVerificationShortFieldMax,
              enabled: !isSubmitting,
              decoration: const InputDecoration(
                label: FieldLabel('Business location'),
                helperText: 'Optional. Town, city or province.',
              ),
              validator: (String? value) =>
                  validateBusinessLocation(value) ??
                  _controller.state.errorFor('business_location'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _businessDescription,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.multiline,
              minLines: 3,
              maxLines: 6,
              maxLength: kSellerVerificationDescriptionMax,
              enabled: !isSubmitting,
              decoration: const InputDecoration(
                label: FieldLabel('Business description'),
                alignLabelWithHint: true,
                helperText:
                    'Optional. What you sell, and how long you have been '
                    'trading.',
              ),
              validator: (String? value) =>
                  validateBusinessDescription(value) ??
                  _controller.state.errorFor('business_description'),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      SellerVerificationAccuracyNotice(),
      const SizedBox(height: AppSpacing.lg),
      FilledButton(
        onPressed: isSubmitting ? null : _goToDocuments,
        child: const Text('Next'),
      ),
    ];
  }

  List<Widget> _documentsStep(
    SellerVerificationDocumentsState documents,
    bool isSubmitting,
  ) {
    final ThemeData theme = Theme.of(context);
    final bool allRequiredUploaded = documents.allRequiredUploaded;

    return <Widget>[
      Text('Government ID Verification', style: theme.textTheme.titleLarge),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Upload the required documents below. Each is uploaded as soon as you '
        'choose it, and you can continue once all show as uploaded.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      Form(
        key: _governmentIdFormKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DropdownButtonFormField<GovernmentIdType>(
              icon: const FieldDropdownIcon(),
              initialValue: _governmentIdType,
              isExpanded: true,
              decoration: InputDecoration(
                label: FieldLabel('Government ID Type'),
                errorText: _controller.state.errorFor('government_id_type'),
              ),
              items: GovernmentIdType.values
                  .map(
                    (GovernmentIdType type) =>
                        DropdownMenuItem<GovernmentIdType>(
                          value: type,
                          child: Text(
                            type.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                  )
                  .toList(growable: false),
              onChanged: isSubmitting
                  ? null
                  : (GovernmentIdType? value) =>
                        setState(() => _governmentIdType = value),
              validator: (GovernmentIdType? value) => value == null
                  ? 'Select a Government ID type.'
                  : _controller.state.errorFor('government_id_type'),
            ),
            if (_governmentIdType == GovernmentIdType.others) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _governmentIdDescription,
                enabled: !isSubmitting,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  label: FieldLabel('Specify Government ID'),
                  errorText: _controller.state.errorFor(
                    'government_id_description',
                  ),
                ),
                validator: (String? value) =>
                    _governmentIdType == GovernmentIdType.others &&
                        (value == null || value.trim().isEmpty)
                    ? 'Specify your Government ID.'
                    : _controller.state.errorFor('government_id_description'),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      SellerVerificationDocumentCard(
        title: 'Government ID — Front',
        instruction:
            'Upload a clear photo or scan of an accepted government-issued ID. '
            'The name and details must be readable.',
        qualityGuidance:
            'The entire ID must be visible, with readable text and no blur, '
            'glare or cropped edges.',
        document: documents.idDocument,
        pickLabel: 'Upload Front ID Image',
        changeLabel: 'Change',
        onPick: () => _pick(VerificationDocumentType.idDocumentFront),
        onRemove: () =>
            _documents.remove(VerificationDocumentType.idDocumentFront),
        onRetry: () =>
            _documents.retry(VerificationDocumentType.idDocumentFront),
        onRetryPreview: () =>
            _documents.loadPreview(VerificationDocumentType.idDocumentFront),
      ),
      if (documents.idDocument.hasFile) ...<Widget>[
        const SizedBox(height: AppSpacing.md),
        Text('Back ID image', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            OutlinedButton(
              onPressed: documents.isBusy ? null : _chooseAndPickBackImage,
              child: const Text('Upload Back ID Image'),
            ),
            OutlinedButton(
              onPressed: documents.isBusy
                  ? null
                  : () => _documents.chooseBackImage(hasNoBackImage: true),
              child: const Text('My ID Has No Back Image'),
            ),
          ],
        ),
        if (documents.hasNoBackImage == true)
          const Text('You declared that your Government ID has no back image.'),
        if (documents.hasNoBackImage == false &&
            (documents.idDocumentBack.hasFile ||
                documents
                    .idDocumentBack
                    .hasPreviousRecordDocument)) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          SellerVerificationDocumentCard(
            title: 'Government ID — Back',
            instruction:
                'Upload a clear image of the back of your Government ID.',
            qualityGuidance: 'Keep the full ID visible and readable.',
            document: documents.idDocumentBack,
            pickLabel: 'Upload Back ID Image',
            changeLabel: 'Replace',
            onPick: () => _pick(VerificationDocumentType.idDocumentBack),
            onRemove: () =>
                _documents.remove(VerificationDocumentType.idDocumentBack),
            onRetry: () =>
                _documents.retry(VerificationDocumentType.idDocumentBack),
            onRetryPreview: () =>
                _documents.loadPreview(VerificationDocumentType.idDocumentBack),
          ),
        ],
        if (documents.hasNoBackImage == null)
          Text(
            'Choose whether your ID has a back image before continuing.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
      ],
      const SizedBox(height: AppSpacing.md),
      SellerVerificationDocumentCard(
        title: 'Proof of Address',
        instruction:
            'Upload a clear photo of a document showing your address, such as '
            'a utility bill or barangay certificate.',
        qualityGuidance:
            'Your name and address must be readable, with no blur, glare or '
            'cropped edges.',
        document: documents.proofOfAddress,
        pickLabel: 'Take Photo',
        changeLabel: 'Change',
        onPick: () => _pick(VerificationDocumentType.proofOfAddress),
        onRemove: () =>
            _documents.remove(VerificationDocumentType.proofOfAddress),
        onRetry: () =>
            _documents.retry(VerificationDocumentType.proofOfAddress),
        onRetryPreview: () =>
            _documents.loadPreview(VerificationDocumentType.proofOfAddress),
      ),
      const SizedBox(height: AppSpacing.md),
      SellerVerificationDocumentCard(
        title: 'Selfie Holding Your ID',
        instruction:
            'Take a clear selfie while holding the same ID beside your face. '
            'Your face and the ID should both be visible in the same photo.',
        qualityGuidance:
            'Use the same ID as above. This is a separate photo — the ID image '
            'cannot be reused here.',
        document: documents.selfie,
        pickLabel: 'Take Photo',
        changeLabel: 'Retake',
        onPick: () => _pick(VerificationDocumentType.selfie),
        onRemove: () => _documents.remove(VerificationDocumentType.selfie),
        onRetry: () => _documents.retry(VerificationDocumentType.selfie),
        onRetryPreview: () =>
            _documents.loadPreview(VerificationDocumentType.selfie),
      ),
      const SizedBox(height: AppSpacing.md),
      SellerVerificationFarmPhotosCard(
        documents: documents,
        onAdd: _pickFarmPhoto,
        onRemove: _documents.removeFarmPhoto,
        onRetry: _documents.retryFarmPhoto,
      ),
      const SizedBox(height: AppSpacing.lg),
      Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton(
              onPressed: documents.isBusy ? null : () => _goToStep(0),
              child: const Text('Back'),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: FilledButton(
              // Gated on the documents being _persisted_, not merely picked:
              // the submit endpoint refuses an application whose documents are
              // missing, so a locally-selected file must not advance the flow.
              onPressed: allRequiredUploaded && !documents.isBusy
                  ? _goToReview
                  : null,
              child: const Text('Next'),
            ),
          ),
        ],
      ),
      if (!allRequiredUploaded) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        Text(
          'All required documents must be uploaded before you can continue.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ];
  }

  List<Widget> _review(
    bool isSubmitting,
    SellerVerificationDocumentsState documents,
  ) {
    final ThemeData theme = Theme.of(context);
    final String? accountName =
        widget.accountName ?? _authController?.state.user?.name;
    final String description = _businessDescription.text.trim();
    final String businessName = _businessName.text.trim();
    final String location = _businessLocation.text.trim();
    final TrinidadLocationCatalog? catalog = _locationCatalog.state.catalog;
    final String address = catalog == null
        ? (_legacyAddress ?? 'Not provided')
        : (_location?.formattedAddress(
                municipality: catalog.municipality,
                province: catalog.province,
              ) ??
              _legacyAddress ??
              'Not provided');

    return <Widget>[
      Text('Review Your Information', style: theme.textTheme.titleLarge),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Check your details before submitting. Submitting sends this to an '
        'administrator and does not guarantee approval.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      SectionCard(
        title: 'Basic Information',
        children: <Widget>[
          if (accountName != null)
            DetailRow(label: 'Full name', value: accountName),
          DetailRow(
            label: 'Phone number',
            value: _phone.text.trim().isEmpty
                ? 'Not provided'
                : _phone.text.trim(),
          ),
          DetailRow(label: 'Address', value: address),
          DetailRow(
            label: 'Business name',
            value: businessName.isEmpty ? 'Not provided' : businessName,
          ),
          DetailRow(
            label: 'Business location',
            value: location.isEmpty ? 'Not provided' : location,
          ),
          DetailRow(
            label: 'Business description',
            value: description.isEmpty ? 'Not provided' : description,
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: isSubmitting ? null : () => _goToStep(0),
              child: const Text('Edit'),
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      SectionCard(
        title: 'Uploaded Documents',
        children: <Widget>[
          _DocumentSummaryRow(
            label: 'Government ID front',
            document: documents.idDocument,
          ),
          _DocumentSummaryRow(
            label: 'Government ID back',
            document: documents.idDocumentBack,
          ),
          DetailRow(
            label: 'Back image declaration',
            value: documents.hasNoBackImage == true
                ? 'Applicant declared no back image'
                : documents.hasNoBackImage == false
                ? 'Back image uploaded'
                : 'Not selected',
          ),
          const SizedBox(height: AppSpacing.xs),
          _DocumentSummaryRow(
            label: 'Proof of Address',
            document: documents.proofOfAddress,
          ),
          const SizedBox(height: AppSpacing.xs),
          _DocumentSummaryRow(
            label: 'Selfie Holding ID',
            document: documents.selfie,
          ),
          const SizedBox(height: AppSpacing.xs),
          DetailRow(
            label: 'Farm photos',
            value: documents.uploadedFarmPhotoCount == 0
                ? 'Not provided'
                : '${documents.uploadedFarmPhotoCount} uploaded',
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: isSubmitting ? null : () => _goToStep(1),
              child: const Text('Edit'),
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton(
              onPressed: isSubmitting ? null : () => _goToStep(1),
              child: const Text('Back'),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: FilledButton(
              // Disabled while submitting, and the controller also refuses a
              // second call in flight. The button stops the tap; the guard stops
              // the request already on its way from being followed by another.
              onPressed: isSubmitting ? null : _submit,
              child: isSubmitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Submit Application'),
            ),
          ),
        ],
      ),
    ];
  }
}

/// One line on the review step summarising a document's persisted state.
class _DocumentSummaryRow extends StatelessWidget {
  const _DocumentSummaryRow({required this.label, required this.document});

  final String label;
  final VerificationDocument document;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool uploaded = document.isUploaded;

    return Row(
      children: <Widget>[
        Icon(
          uploaded ? Icons.check_circle : Icons.error_outline,
          size: 18,
          color: uploaded ? AppColors.success : AppColors.error,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
        Text(
          uploaded ? 'Uploaded' : 'Missing',
          style: theme.textTheme.labelSmall?.copyWith(
            color: uploaded ? AppColors.success : AppColors.error,
          ),
        ),
      ],
    );
  }
}

/// A form-level failure, e.g. a `403` because the account is already a seller or
/// a `5xx` from the submission.
class _FormErrorBanner extends StatelessWidget {
  const _FormErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: const Border(
          left: BorderSide(color: AppColors.error, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline, size: 20, color: AppColors.error),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
