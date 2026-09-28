import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/seller_verification.dart';
import '../../../repositories/seller_verification_repository.dart';
import 'seller_verification_state.dart';

/// Presentation logic for seller verification.
///
/// The only thing that mutates [state]. Screens call these methods and listen.
///
/// ## The rule this class exists to enforce
///
/// **Submitting a verification must never make anybody a seller.** The account's
/// capability comes from `/auth/me` and is changed only by an administrator
/// approving the record. So a successful [submit] publishes the server's
/// `submitted` record and stops there — it does not touch `AuthController`, does
/// not set `seller_capability`, and does not optimistically flip a chip to
/// "Seller". A user who has just applied and an approved seller are in
/// materially different states, and only the server can tell them apart
/// (functional documentation §2.6).
///
/// ## Errors
///
/// Each `ApiErrorKind` is handled for what it *is*, because the three that matter
/// here mean very different things to the person reading the screen:
///
///  * `409` — already in the queue. Not a fault and not a validation problem;
///    the response lands in [SellerVerificationState.conflictMessage] and the
///    read is repeated so the screen settles on the real state.
///  * `422` — per-field messages, shown beside the fields.
///  * `403` — the account is already an approved seller, so the form is
///    meaningless. Reported as an error rather than being swallowed.
class SellerVerificationController extends ChangeNotifier {
  /// Creates the controller.
  ///
  /// [onCapabilityMayHaveChanged] is called when a read shows an approved
  /// verification, so the session's user can be re-read from `/auth/me`. It is
  /// optional: with `null`, the account details are not refreshed and the
  /// verification status on screen is still correct, which is what tests want.
  SellerVerificationController(
    this._repository, {
    Future<bool> Function()? onCapabilityMayHaveChanged,
    // An initializing formal cannot be used for a named parameter — Dart
    // forbids a leading underscore in one — so the assignment is spelled out.
    // ignore: prefer_initializing_formals
  }) : _onCapabilityMayHaveChanged = onCapabilityMayHaveChanged;

  final SellerVerificationRepository _repository;

  /// Re-reads `/auth/me` when a read shows an approved verification.
  ///
  /// Injected rather than a direct `AuthController` reference: this feature must
  /// not depend on the auth feature, and `main.dart` is where the two are wired
  /// together. A `null` callback — in tests, or anywhere the session is not in
  /// play — simply means the account details are not refreshed, and the
  /// verification status on screen is still correct.
  final Future<bool> Function()? _onCapabilityMayHaveChanged;

  SellerVerificationState _state = const SellerVerificationState();
  SellerVerificationState get state => _state;

  bool _disposed = false;

  /// Guards against a second read while one is in flight.
  ///
  /// The screen calls [load] from `initState`; a rebuild that re-enters it must
  /// not cost a second request, and a rapid "open the form, back, open again"
  /// must not produce two.
  bool _loading = false;

  /// Set once [onCapabilityMayHaveChanged] has been called, so a screen that is
  /// rebuilt and re-read does not re-request `/auth/me` on every visit.
  bool _capabilityRefreshRequested = false;

  /// Incremented per read; a response from a superseded read is discarded.
  int _generation = 0;

  /// Reads the caller's current verification.
  ///
  /// A `null` result is the normal "never submitted" state, not a failure, and
  /// is published as [SellerVerificationUiStatus.notSubmitted].
  Future<void> load() async {
    if (_loading) {
      return;
    }
    _loading = true;

    final int generation = ++_generation;
    _set(_state.copyWith(status: SellerVerificationUiStatus.loading, clearError: true));

    try {
      final SellerVerification? verification = await _repository.current();

      if (_disposed || generation != _generation) {
        return;
      }

      if (verification == null) {
        _set(
          _state.copyWith(
            status: SellerVerificationUiStatus.notSubmitted,
            clearVerification: true,
          ),
        );
        return;
      }

      _set(
        _state.copyWith(
          status: _statusFor(verification),
          verification: verification,
        ),
      );
      _maybeRefreshCapability(verification);
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: SellerVerificationUiStatus.failed,
          errorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: SellerVerificationUiStatus.failed,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
    } finally {
      _loading = false;
    }
  }

  /// Files a verification. Returns `true` when the record was created.
  ///
  /// A second call while a submission is in flight returns `false` without
  /// touching the network. That is the duplicate-submission guard, and it lives
  /// here rather than only as a disabled button: a disabled button stops a tap,
  /// but it does not stop the request already in flight from being followed by
  /// another one, and the server would answer the second with a `409` that the
  /// user did not cause.
  ///
  /// On success the screen moves to the pending state. `seller_capability` is
  /// untouched — see the class documentation.
  Future<bool> submit({
    required String businessName,
    String? businessLocation,
    String? businessDescription,
    String? idDocumentRef,
  }) async {
    if (_state.isBusy) {
      return false;
    }

    _set(
      _state.copyWith(
        status: SellerVerificationUiStatus.submitting,
        clearError: true,
        clearConflict: true,
        validationErrors: const <String, List<String>>{},
      ),
    );

    try {
      final SellerVerification verification = await _repository.submit(
        businessName: businessName,
        businessLocation: businessLocation,
        businessDescription: businessDescription,
        idDocumentRef: idDocumentRef,
      );

      if (_disposed) {
        return false;
      }

      // The server's own record, not an optimistic guess. It is `submitted` by
      // construction, but the status is taken from the response so a server that
      // advanced it cannot be contradicted by the client.
      _set(
        _state.copyWith(
          status: _statusFor(verification),
          verification: verification,
        ),
      );
      // A submission is never approved by being filed, so `seller_capability`
      // cannot have changed and is deliberately not refreshed here. The check is
      // made anyway rather than assumed: it costs nothing when the answer is
      // "no", and if the server ever did approve on submission this is where the
      // account would pick that up instead of the screen lying about it.
      _maybeRefreshCapability(verification);
      return true;
    } on ApiException catch (error) {
      if (_disposed) {
        return false;
      }

      switch (error.kind) {
        case ApiErrorKind.conflict:
          // Already in the queue. Re-read so the screen shows the real record
          // rather than the form the user just tried to submit from.
          _set(
            _state.copyWith(
              status: SellerVerificationUiStatus.awaitingReview,
              conflictMessage: error.message,
            ),
          );
          unawaited(load());
        case ApiErrorKind.validation:
          _set(
            _state.copyWith(
              status: _statusBeforeSubmit(),
              errorMessage: error.message,
              validationErrors: error.validationErrors,
            ),
          );
        case ApiErrorKind.forbidden:
          // Already an approved seller. The form should not have been reachable,
          // so this is a state the app did not anticipate; saying so is more
          // useful than a validation message about business names.
          _set(
            _state.copyWith(
              status: _statusBeforeSubmit(),
              errorMessage:
                  error.message.isEmpty
                      ? 'This account is already an approved seller.'
                      : error.message,
            ),
          );
        default:
          _set(
            _state.copyWith(
              status: _statusBeforeSubmit(),
              errorMessage: error.message,
            ),
          );
      }
      return false;
    } on Object {
      if (_disposed) {
        return false;
      }
      _set(
        _state.copyWith(
          status: _statusBeforeSubmit(),
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
      return false;
    }
  }

  /// Discards a form-level error so a retry starts clean.
  void clearError() {
    if (_state.errorMessage == null &&
        _state.conflictMessage == null &&
        _state.validationErrors.isEmpty) {
      return;
    }
    _set(
      _state.copyWith(
        clearError: true,
        clearConflict: true,
        validationErrors: const <String, List<String>>{},
      ),
    );
  }

  /// Re-reads `/auth/me` when the record is approved, at most once per session.
  ///
  /// The one place this app reacts to a change in `seller_capability`, and it
  /// does so by *asking the server* — the capability is never written from a
  /// verification status. That is the whole point: an approved record and a
  /// seller account are related but separate facts, and only `/auth/me` decides
  /// the second.
  ///
  /// Deliberately not awaited. This runs after the status has already been
  /// published, so the screen shows "approved" without waiting on a second
  /// request, and a slow or failed `/auth/me` cannot delay or undo it — it would
  /// only leave the account card showing the previous capability until the next
  /// read, which is honest.
  void _maybeRefreshCapability(SellerVerification verification) {
    if (_capabilityRefreshRequested || !verification.isApproved) {
      return;
    }
    final Future<bool> Function()? refresh = _onCapabilityMayHaveChanged;
    if (refresh == null) {
      return;
    }

    _capabilityRefreshRequested = true;
    unawaited(refresh());
  }

  /// The status to return to after a submission that failed.
  ///
  /// A failed submission must not destroy the state the user was in — returning
  /// to `initial` would blank the screen, and returning to `submitting` would
  /// leave the button spinning. The prior business status is recomputed from the
  /// record still held, which is exactly the state the form was opened from.
  SellerVerificationUiStatus _statusBeforeSubmit() {
    final SellerVerification? current = _state.verification;
    return current == null
        ? SellerVerificationUiStatus.notSubmitted
        : _statusFor(current);
  }

  /// Maps a server record to a screen state.
  ///
  /// The record is the only input. `seller_capability` is not consulted: this
  /// phase reports what the verification says, and the capability chip reads
  /// `/auth/me`.
  ///
  /// The two enums are deliberately spelled out on both sides of the `=>`: the
  /// left is the server's [SellerVerificationStatus], the right is the screen's
  /// [SellerVerificationUiStatus], and an exhaustive switch over the former is
  /// what makes adding a fifth server state a compile error here rather than a
  /// silent fallthrough.
  static SellerVerificationUiStatus _statusFor(SellerVerification verification) {
    return switch (verification.status) {
      SellerVerificationStatus.submitted ||
      SellerVerificationStatus.pendingReview =>
        SellerVerificationUiStatus.awaitingReview,
      SellerVerificationStatus.approved => SellerVerificationUiStatus.approved,
      SellerVerificationStatus.rejected => SellerVerificationUiStatus.rejected,
    };
  }

  void _set(SellerVerificationState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
