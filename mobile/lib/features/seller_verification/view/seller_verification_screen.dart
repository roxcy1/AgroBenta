import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../models/seller_verification.dart';
import '../state/seller_verification_controller.dart';
import '../state/seller_verification_scope.dart';
import '../state/seller_verification_state.dart';
import 'seller_verification_form_screen.dart';
import 'seller_verification_views.dart';

/// The seller verification status screen, and the entry point to the form.
///
/// Reached from the Home screen's seller card, and readable at any time: it shows
/// the caller's current verification, whatever that is, and offers exactly one
/// action per state — apply, wait, resubmit, or nothing.
///
/// ## What this screen does not do
///
/// It never grants seller capability and never decides the account is a seller.
/// An approved verification is reported as a fact about the *application*; the
/// account's capability is read from `/auth/me`. It also never offers a second
/// application while one is open, because the server answers that with a `409`.
class SellerVerificationScreen extends StatefulWidget {
  const SellerVerificationScreen({this.accountName, this.pickImage, super.key});

  /// The caller's full name, from the account, shown read-only on the form.
  ///
  /// Optional: the screen is a status hub first, and the name is only needed by
  /// the form one push deeper. The profile screen supplies it from `/auth/me`; a
  /// tree without it simply omits the read-only row.
  final String? accountName;

  /// Overrides how an image is picked on the form, for tests.
  ///
  /// Forwarded verbatim to [SellerVerificationFormScreen]. `null` in production,
  /// where the form uses the platform picker.
  final Future<XFile?> Function(VerificationDocumentType type)? pickImage;

  @override
  State<SellerVerificationScreen> createState() =>
      _SellerVerificationScreenState();
}

class _SellerVerificationScreenState extends State<SellerVerificationScreen> {
  late final SellerVerificationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SellerVerificationScope.readOf(context);
    // Deferred out of the build phase on purpose. `load()` publishes `loading`
    // synchronously, and this screen is reached from the Home screen's seller
    // card — which is *already* listening to this controller. Notifying from
    // `initState` would rebuild that ancestor while the tree is being assembled,
    // which Flutter rejects. Waiting a frame puts the read after the build, and
    // the controller's own guard keeps it to one request.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.load();
      }
    });
  }

  void _openForm({required bool isResubmission}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => SellerVerificationFormScreen(
          isResubmission: isResubmission,
          accountName: widget.accountName,
          pickImage: widget.pickImage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // The title depends on the state, which arrives asynchronously, so it
        // listens to the controller like the body does. Without this the app bar
        // would keep the title from the frame it was first built in.
        title: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? child) => Text(_title()),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? child) {
            final SellerVerificationState state = _controller.state;

            if (state.status == SellerVerificationUiStatus.loading ||
                state.status == SellerVerificationUiStatus.initial) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state.status == SellerVerificationUiStatus.failed) {
              return SellerVerificationErrorState(
                message: state.errorMessage ?? 'Something went wrong.',
                onRetry: _controller.load,
              );
            }

            return RefreshIndicator(
              onRefresh: _controller.load,
              child: ListView(
                // Always scrollable so pull-to-refresh works even when the
                // content is shorter than the viewport — otherwise the gesture
                // silently does nothing on a small screen.
                physics: const AlwaysScrollableScrollPhysics(),
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
                          _statusView(state),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// The app bar title for the current state.
  ///
  /// "Become a Seller" introduces the flow, matching the first entry screen; once
  /// there is a record the screen is the reference's "Seller Application" details
  /// view. Both are the same route entered at different states.
  String _title() {
    final SellerVerificationUiStatus status = _controller.state.status;
    if (status == SellerVerificationUiStatus.initial ||
        status == SellerVerificationUiStatus.loading ||
        status == SellerVerificationUiStatus.failed) {
      return 'Seller verification';
    }
    return status == SellerVerificationUiStatus.notSubmitted
        ? 'Become a Seller'
        : 'Seller Application';
  }

  /// The one view for the current state.
  ///
  /// [SellerVerificationUiStatus.submitting] has no case: a submission happens on
  /// the form screen, and this screen is not on top of it while that is in
  /// flight. It falls through to [SellerVerificationUiStatus.awaitingReview] so
  /// the screen still reads correctly if it is ever rebuilt mid-submission.
  Widget _statusView(SellerVerificationState state) {
    final SellerVerification? verification = state.verification;

    // No record means the user has never applied, whatever the presentation
    // status says. Established once here so every case below can rely on the
    // record being present, and so a status that arrived without one renders the
    // honest "never applied" view instead of dereferencing null — or, worse,
    // substituting a fabricated record to display.
    void start() => _openForm(isResubmission: false);
    if (verification == null) {
      return SellerVerificationIntroView(onStart: start);
    }

    return switch (state.status) {
      SellerVerificationUiStatus.rejected => SellerVerificationRejectedView(
        verification: verification,
        onResubmit: () => _openForm(isResubmission: true),
      ),
      SellerVerificationUiStatus.approved => SellerVerificationApprovedView(
        verification: verification,
      ),
      _ => SellerVerificationAwaitingReviewView(verification: verification),
    };
  }
}
