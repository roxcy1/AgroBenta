/// The response envelope used by the AgroBenta Laravel API.
///
/// Controllers return:
///
/// ```json
/// { "success": true, "message": "Logged in successfully.", "data": { } }
/// ```
///
/// `message` is absent on some read endpoints (for example the admin `me`
/// response), so it is nullable. `data` is present on success and may be any
/// JSON value.
///
/// A 2xx body that carries `success` but no `data` at all — Laravel's
/// message-only responses, such as `POST /auth/logout` — is normalised by
/// [ApiClient] before it reaches this class, so by the time a response is
/// parsed here `data` is always present and may legitimately be `null`.
///
/// [ApiClient] unwraps this envelope and hands feature code the `data` payload
/// only, so screens never reach for `['data']` themselves.
///
/// ## The one exception
///
/// `GET /api/user` returns the raw Eloquent user with **no** envelope. That
/// endpoint is not part of the mobile contract; see the API GAP register in
/// `mobile/AGENTS.md`. If an unwrapped response is ever genuinely required,
/// handle it explicitly at the call site rather than weakening this class.
library;

class ApiEnvelope<T> {
  const ApiEnvelope({required this.success, this.message, required this.data});

  /// Parses the envelope and delegates the `data` payload to [fromData].
  ///
  /// Throws [FormatException] when required fields are missing or have the
  /// wrong type, so a contract change surfaces as a loud, locatable failure
  /// rather than a null that travels deep into the widget tree.
  factory ApiEnvelope.fromJson(
    Map<String, dynamic> json,
    T Function(Object? data) fromData,
  ) {
    final Object? success = json['success'];
    if (success is! bool) {
      throw FormatException(
        'API response is missing a boolean "success" field.',
        json.toString(),
      );
    }

    final Object? message = json['message'];
    if (message != null && message is! String) {
      throw FormatException(
        'API response field "message" must be a string or null.',
        json.toString(),
      );
    }

    if (!json.containsKey('data')) {
      throw FormatException(
        'API response is missing a "data" field.',
        json.toString(),
      );
    }

    return ApiEnvelope<T>(
      success: success,
      message: message as String?,
      data: fromData(json['data']),
    );
  }

  final bool success;

  /// Human-readable server message. Suitable for surfacing in a snackbar when
  /// it is meaningful, but never assume it is present.
  final String? message;

  final T data;
}
