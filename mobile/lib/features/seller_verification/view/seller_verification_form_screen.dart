import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/seller_verification.dart';
import '../state/seller_verification_controller.dart';
import '../state/seller_verification_scope.dart';
import '../state/seller_verification_state.dart';
import 'seller_verification_validators.dart';
import 'seller_verification_views.dart';

/// The seller verification form — `POST /api/seller-verification`.
///
/// Four fields, and only the four the contract accepts: business name, location,
/// description, and an ID document **reference**. There is no file picker, and
/// that is a contract fact rather than an omission — no upload endpoint exists,
/// so a picker would collect a file the app had nowhere to send.
///
/// The same screen serves a first application and a resubmission; [isResubmission]
/// only changes the wording. The two are the same request: a resubmission is a
/// **new** record, never an edit of the rejected one, which is why the button here
/// says "Resubmit" and the rejected record stays on file.
///
/// ## `id_document_ref` is a reference, not a document
///
/// The label and the helper text both say so, because "ID document" alone reads
/// as "attach your ID" and a seller who cannot read the field description may
/// reasonably look for a camera button that does not exist.
class SellerVerificationFormScreen extends StatefulWidget {
  const SellerVerificationFormScreen({
    required this.isResubmission,
    super.key,
  });

  /// Whether this is a resubmission after a rejection.
  ///
  /// Affects the title and the button label only. It never changes the request.
  final bool isResubmission;

  @override
  State<SellerVerificationFormScreen> createState() =>
      _SellerVerificationFormScreenState();
}

class _SellerVerificationFormScreenState
    extends State<SellerVerificationFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _businessName = TextEditingController();
  final TextEditingController _businessLocation = TextEditingController();
  final TextEditingController _businessDescription = TextEditingController();
  final TextEditingController _idDocumentRef = TextEditingController();

  late final SellerVerificationController _controller;

  /// The field errors currently on screen, so a repeat of the same server error
  /// does not re-validate for nothing.
  Map<String, List<String>> _displayedErrors = const <String, List<String>>{};

  @override
  void initState() {
    super.initState();
    // `readOf`, not `of`: a dependency cannot be registered from `initState`, and
    // the screen rebuilds on every keystroke otherwise.
    _controller = SellerVerificationScope.readOf(context);

    // A resubmission starts from what was rejected, so the seller corrects the
    // fields that were the problem instead of retyping four of them. These are
    // the server's own values from the record already on screen — no local copy
    // of the application is kept anywhere.
    final SellerVerification? previous = _controller.state.verification;
    if (widget.isResubmission && previous != null) {
      _businessName.text = previous.businessName;
      _businessLocation.text = previous.businessLocation ?? '';
      _businessDescription.text = previous.businessDescription ?? '';
      _idDocumentRef.text = previous.idDocumentRef ?? '';
    }
  }

  /// A `TextFormField` runs its validator when its value changes and when
  /// `validate()` is called — not when the widget rebuilds. A `422` therefore
  /// arrives after the last validation and would never appear on the field
  /// without this.
  ///
  /// Called from the [ListenableBuilder] rather than from `didChangeDependencies`
  /// because a `422` arrives as a controller notification, and this screen
  /// deliberately does **not** depend on the scope: it listens to the controller
  /// instead. `didChangeDependencies` only runs when an inherited widget it is
  /// registered against changes, so with the form built this way the server's
  /// field errors would sit in the state and never reach the fields.
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
    _idDocumentRef.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final bool created = await _controller.submit(
      businessName: _businessName.text,
      businessLocation: _businessLocation.text,
      businessDescription: _businessDescription.text,
      idDocumentRef: _idDocumentRef.text,
    );

    // The controller holds the new record, so the status screen behind this one
    // is already showing it. Returning without a `true` here would also be
    // correct behaviour-wise, and a result value would be free to misuse later.
    if (created && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isResubmission ? 'Resubmit verification' : 'Become a Seller'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? child) {
            final SellerVerificationState state = _controller.state;
            final bool isSubmitting =
                state.status == SellerVerificationUiStatus.submitting;

            // Must run on every state change, including one that only carries
            // `validationErrors` — see [_revealServerFieldErrors].
            _revealServerFieldErrors(state.validationErrors);

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              children: <Widget>[
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
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
                        Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
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
                                    state.errorFor('business_name'),
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
                                    state.errorFor('business_location'),
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
                                      'Optional. What you sell, and how long you '
                                      'have been trading.',
                                ),
                                validator: (String? value) =>
                                    validateBusinessDescription(value) ??
                                    state.errorFor('business_description'),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              TextFormField(
                                controller: _idDocumentRef,
                                textInputAction: TextInputAction.done,
                                maxLength: kSellerVerificationShortFieldMax,
                                enabled: !isSubmitting,
                                decoration: const InputDecoration(
                                  labelText: 'ID document reference',
                                  helperText:
                                      'Optional. Type a reference such as a '
                                      'document number — do not send the document '
                                      'itself.',
                                ),
                                onFieldSubmitted: (_) => _submit(),
                                validator: (String? value) =>
                                    validateIdDocumentRef(value) ??
                                    state.errorFor('id_document_ref'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        FilledButton(
                          // Disabled while submitting, and the controller also
                          // refuses a second call in flight. The button stops the
                          // tap; the guard stops the request that is already on
                          // its way from being followed by another.
                          onPressed: isSubmitting ? null : _submit,
                          child:
                              isSubmitting
                                  ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : Text(
                                    widget.isResubmission
                                        ? 'Resubmit verification'
                                        : 'Submit application',
                                  ),
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
