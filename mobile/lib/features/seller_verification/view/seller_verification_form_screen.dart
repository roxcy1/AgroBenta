import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/seller_verification.dart';
import '../../../widgets/detail_row.dart';
import '../../../widgets/section_card.dart';
import '../state/seller_verification_controller.dart';
import '../state/seller_verification_documents_controller.dart';
import '../state/seller_verification_documents_state.dart';
import '../state/seller_verification_scope.dart';
import '../state/seller_verification_state.dart';
import '../widgets/seller_verification_document_card.dart';
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
/// The form submits `business_name`, `business_location` and
/// `business_description` — the allow-listed fields
/// `SubmitSellerVerificationRequest` accepts. Full name is shown read-only from
/// the account ([accountName]) because it comes from `/auth/me`, not the
/// application. Phone number is not collected: there is no column. The two
/// required evidence documents are uploaded through
/// `/seller-verification/documents` before submission, because the submit
/// endpoint refuses an application whose documents are missing (a `422`). The app
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
  final TextEditingController _businessName = TextEditingController();
  final TextEditingController _businessLocation = TextEditingController();
  final TextEditingController _businessDescription = TextEditingController();

  late final SellerVerificationController _controller;
  late final SellerVerificationDocumentsController _documents;

  /// Zero-based index of the step being shown.
  int _step = 0;

  /// The field errors currently on screen, so a repeat of the same server error
  /// does not re-validate for nothing.
  Map<String, List<String>> _displayedErrors = const <String, List<String>>{};

  @override
  void initState() {
    super.initState();
    // `readOf`, not `of`: a dependency cannot be registered from `initState`, and
    // the screen rebuilds on every keystroke otherwise.
    _controller = SellerVerificationScope.readOf(context);
    _documents = SellerVerificationDocumentsController(
      SellerVerificationScope.repositoryOf(context),
    );

    final SellerVerification? previous = _controller.state.verification;

    // A resubmission starts from what was rejected, so the seller corrects the
    // fields that were the problem instead of retyping them. These are the
    // server's own values from the record already on screen — no local copy of
    // the application is kept anywhere.
    if (widget.isResubmission && previous != null) {
      _businessName.text = previous.businessName;
      _businessLocation.text = previous.businessLocation ?? '';
      _businessDescription.text = previous.businessDescription ?? '';
    }

    // Seed the document slots from the record so a resubmission shows which
    // documents the server still holds. On a first application this is a no-op.
    _documents.seedFrom(previous);
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
      }
    });
  }

  @override
  void dispose() {
    _businessName.dispose();
    _businessLocation.dispose();
    _businessDescription.dispose();
    _documents.dispose();
    super.dispose();
  }

  void _goToDocuments() {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() => _step = 1);
    }
  }

  void _goToReview() {
    if (_documents.state.bothUploaded) {
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

  Future<void> _submit() async {
    final bool created = await _controller.submit(
      businessName: _businessName.text,
      businessLocation: _businessLocation.text,
      businessDescription: _businessDescription.text,
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

    // A `422` names fields that live on the first step, so return there and
    // reset the error cache so the field validators run once the fields mount.
    if (_controller.state.validationErrors.isNotEmpty) {
      setState(() {
        // Document field errors (`id_document`, `selfie`) belong on the
        // Documents step; business field errors on Basic Information.
        _step = _controller.state.validationErrors.keys.any(
          (String key) =>
              key == VerificationDocumentType.idDocument.value ||
              key == VerificationDocumentType.selfie.value,
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
          listenable: Listenable.merge(<Listenable>[_controller, _documents]),
          builder: (BuildContext context, Widget? child) {
            final SellerVerificationState state = _controller.state;
            final SellerVerificationDocumentsState documents =
                _documents.state;
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
                          1 => _documentsStep(documents),
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
            if (widget.accountName != null) ...<Widget>[
              TextFormField(
                initialValue: widget.accountName,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  helperText: 'From your account — cannot be changed here.',
                  suffixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            TextFormField(
              controller: _businessName,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: kSellerVerificationShortFieldMax,
              enabled: !isSubmitting,
              decoration: const InputDecoration(
                labelText: 'Business name',
                helperText: 'Required.',
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
                labelText: 'Business location',
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
                labelText: 'Business description',
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

  List<Widget> _documentsStep(SellerVerificationDocumentsState documents) {
    final ThemeData theme = Theme.of(context);
    final bool bothUploaded = documents.bothUploaded;

    return <Widget>[
      Text('Upload Required Documents', style: theme.textTheme.titleLarge),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Upload both documents below. Each is uploaded as soon as you choose '
        'it, and you can continue once both show as uploaded.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      SellerVerificationDocumentCard(
        title: 'Valid Government-Issued ID',
        instruction:
            'Upload a clear photo or scan of an accepted government-issued ID. '
            'The name and details must be readable.',
        qualityGuidance:
            'The entire ID must be visible, with readable text and no blur, '
            'glare or cropped edges.',
        document: documents.idDocument,
        pickLabel: 'Take Photo',
        changeLabel: 'Change',
        onPick: () => _pick(VerificationDocumentType.idDocument),
        onRemove: () => _documents.remove(VerificationDocumentType.idDocument),
        onRetry: () => _documents.retry(VerificationDocumentType.idDocument),
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
              // Gated on both documents being _persisted_, not merely picked:
              // the submit endpoint refuses an application whose documents are
              // missing, so a locally-selected file must not advance the flow.
              onPressed: bothUploaded && !documents.isBusy ? _goToReview : null,
              child: const Text('Next'),
            ),
          ),
        ],
      ),
      if (!bothUploaded) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Both documents must be uploaded before you can continue.',
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
    final String location = _businessLocation.text.trim();
    final String description = _businessDescription.text.trim();

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
          if (widget.accountName != null)
            DetailRow(label: 'Full name', value: widget.accountName!),
          DetailRow(label: 'Business name', value: _businessName.text.trim()),
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
            label: 'Government-Issued ID',
            document: documents.idDocument,
          ),
          const SizedBox(height: AppSpacing.xs),
          _DocumentSummaryRow(
            label: 'Selfie Holding ID',
            document: documents.selfie,
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
