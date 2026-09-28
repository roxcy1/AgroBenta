/// A failure returned by the AgroBenta API, or a transport failure on the way
/// to it.
///
/// Feature code should catch [ApiException] and branch on [kind] rather than
/// inspecting HTTP status codes directly. The mapping from status to [kind] is
/// centralised in `ApiClient` so it is defined once.
library;

enum ApiErrorKind {
  /// The device could not reach the server at all: no connectivity, DNS
  /// failure, TLS failure, or the request timed out.
  ///
  /// On an Android emulator this is frequently a wrong base URL — check
  /// `AppConfig.apiBaseUrl` and the `10.0.2.2` rule before assuming the
  /// network is down.
  network,

  /// 401. The token is missing, malformed, revoked, or expired.
  ///
  /// The client clears the stored token before throwing this, so the app is
  /// left signed out.
  unauthorized,

  /// 403. Authenticated, but not permitted.
  ///
  /// The AgroBenta backend returns 403 from the `admin` middleware when a
  /// non-administrator token calls an admin route. A correctly-scoped mobile
  /// token should never trigger this; if it does, treat it as a contract
  /// mismatch and report it rather than showing a generic error.
  forbidden,

  /// 404. Endpoint or record does not exist.
  notFound,

  /// 409. The request conflicts with the current state of the resource.
  ///
  /// Only one endpoint in this app's contract returns it:
  /// `POST /seller-verification` when the caller already has a verification
  /// open for review. It is a distinct kind rather than being folded into
  /// `validation` because the payload is not wrong — the user submitted
  /// something perfectly valid, and retrying it will not help until an
  /// administrator decides. A form that treated it as a field error would invite
  /// the user to keep editing fields that are already correct.
  conflict,

  /// 422. Form Request validation failed. [validationErrors] carries the
  /// per-field messages Laravel returns under `errors`.
  validation,

  /// 429. Rate limited. The admin login route is throttled at 10/minute.
  rateLimited,

  /// 5xx. The server failed. [serverMessage] may hold a Laravel error string.
  server,

  /// The response was not the shape we expected: unparseable JSON, a missing
  /// envelope, or a field whose type changed.
  ///
  /// This usually means an API contract changed. Do not paper over it with a
  /// default value.
  malformedResponse,
}

class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.serverMessage,
    this.validationErrors = const <String, List<String>>{},
    this.cause,
  });

  /// Convenience constructor for [ApiErrorKind.network].
  const ApiException.network({required String message, Object? cause})
    : this(kind: ApiErrorKind.network, message: message, cause: cause);

  /// Convenience constructor for [ApiErrorKind.malformedResponse].
  const ApiException.malformedResponse({
    required String message,
    Object? cause,
  }) : this(
         kind: ApiErrorKind.malformedResponse,
         message: message,
         cause: cause,
       );

  final ApiErrorKind kind;

  /// A message safe to show to a user. Derived from the server's `message`
  /// field where one was supplied, otherwise from a sensible default per
  /// [kind].
  final String message;

  /// HTTP status code, or `null` for [ApiErrorKind.network].
  final int? statusCode;

  /// Per-field validation messages, keyed by field name. Populated for
  /// [ApiErrorKind.validation] (Laravel 422).
  final Map<String, List<String>> validationErrors;

  /// Server-side detail, when the backend returned a meaningful one. Useful in
  /// logs; not necessarily suitable for display.
  final String? serverMessage;

  /// The underlying error, when this exception wraps one.
  final Object? cause;

  /// True when the session is no longer usable and the user must sign in again.
  bool get requiresReauthentication => kind == ApiErrorKind.unauthorized;

  @override
  String toString() =>
      'ApiException(${kind.name}'
      '${statusCode == null ? '' : ', status $statusCode'}): $message';
}
