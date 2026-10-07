import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/api_envelope.dart';
import '../config/app_config.dart';
import '../constants/api_constants.dart';
import '../storage/token_store.dart';
import 'api_exception.dart';

/// The single point through which every HTTP request to the AgroBenta Laravel
/// API passes.
///
/// Responsibilities, and deliberately nothing else:
///
///  * attach the Sanctum bearer token when one is stored;
///  * send JSON headers;
///  * enforce a request timeout;
///  * unwrap the `{ success, message, data }` envelope;
///  * translate transport and HTTP failures into [ApiException];
///  * clear the stored token on 401.
///
/// It knows nothing about any particular endpoint or feature. Endpoint paths
/// live with the feature that calls them.
///
/// ## Why the 401 handling lives here
///
/// The Admin Web handles 401 in an axios response interceptor
/// (`frontend/src/lib/api.ts`). The equivalent hook in `package:http` is this
/// class, because `package:http` has no interceptor concept. Doing it in one
/// place means no feature can forget it and no screen can end up retrying a
/// request with a token the server has already revoked.
class ApiClient {
  ApiClient({
    // Named private fields are exposed under their underscore-stripped public
    // name, so callers write `ApiClient(tokenStorage: ...)`.
    required this._tokenStorage,
    http.Client? httpClient,
    Duration? timeout,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _timeout = timeout ?? ApiConstants.defaultTimeout;

  final TokenStore _tokenStorage;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Duration _timeout;

  /// The API root this client is pointed at. Exposed for diagnostics and
  /// tests; never used to construct URLs outside [AppConfig].
  String get baseUrl => AppConfig.apiBaseUrl;

  /// Performs a `GET` and returns the unwrapped `data` payload.
  Future<T> get<T>(
    String path, {
    required T Function(Object? data) parse,
    Map<String, dynamic>? query,
  }) {
    return _send<T>(method: 'GET', path: path, parse: parse, query: query);
  }

  /// Performs a `POST` and returns the unwrapped `data` payload.
  Future<T> post<T>(
    String path, {
    Object? body,
    required T Function(Object? data) parse,
    Map<String, dynamic>? query,
  }) {
    return _send<T>(
      method: 'POST',
      path: path,
      body: body,
      parse: parse,
      query: query,
    );
  }

  /// Performs a `PUT` and returns the unwrapped `data` payload.
  Future<T> put<T>(
    String path, {
    Object? body,
    required T Function(Object? data) parse,
    Map<String, dynamic>? query,
  }) {
    return _send<T>(
      method: 'PUT',
      path: path,
      body: body,
      parse: parse,
      query: query,
    );
  }

  /// Performs a `PATCH` and returns the unwrapped `data` payload.
  Future<T> patch<T>(
    String path, {
    Object? body,
    required T Function(Object? data) parse,
    Map<String, dynamic>? query,
  }) {
    return _send<T>(
      method: 'PATCH',
      path: path,
      body: body,
      parse: parse,
      query: query,
    );
  }

  /// Performs a `DELETE` and returns the unwrapped `data` payload.
  ///
  /// Laravel endpoints that return 204 have no body. Pass
  /// `parse: (_) => null` for those; the envelope unwrapping is skipped when the
  /// response has no body at all.
  Future<T> delete<T>(
    String path, {
    Object? body,
    required T Function(Object? data) parse,
    Map<String, dynamic>? query,
  }) {
    return _send<T>(
      method: 'DELETE',
      path: path,
      body: body,
      parse: parse,
      query: query,
    );
  }

  /// Releases the underlying HTTP connection pool.
  ///
  /// Only closes a client this instance created; an injected client is owned by
  /// the caller.
  void close() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  Future<T> _send<T>({
    required String method,
    required String path,
    Object? body,
    required T Function(Object? data) parse,
    Map<String, dynamic>? query,
  }) async {
    final (response: http.Response response, authenticated: bool sentToken) =
        await _perform(method: method, path: path, body: body, query: query);

    // 204 and 205 carry no body by definition. Laravel uses 204 for deletes.
    if (response.statusCode == 204 || response.statusCode == 205) {
      return parse(null);
    }

    // Decode leniently. A non-JSON body on an *error* response is normal —
    // Nginx returns an HTML 502 when the PHP container is down, and Laravel's
    // `abort(403, '...')` returns a bare JSON string. The status code is the
    // more reliable signal, so a decode failure must not mask it.
    bool decodeFailed = false;
    Object? decoded;
    try {
      decoded = _decodeBody(response);
    } on ApiException {
      decodeFailed = true;
    }

    if (_isSuccessStatus(response.statusCode)) {
      if (decodeFailed) {
        throw const ApiException.malformedResponse(
          message: 'The server returned a response that was not valid JSON.',
        );
      }

      try {
        final Map<String, dynamic> body = _successBody(decoded!);
        final ApiEnvelope<Object?> envelope = ApiEnvelope<Object?>.fromJson(
          body,
          (Object? data) => data,
        );

        if (!envelope.success) {
          throw ApiException(
            kind: ApiErrorKind.server,
            message: envelope.message ?? 'The server rejected the request.',
            statusCode: response.statusCode,
            serverMessage: envelope.message,
          );
        }

        return parse(envelope.data);
      } on FormatException catch (error) {
        throw ApiException.malformedResponse(
          message: 'The server returned an unexpected response shape.',
          cause: error,
        );
      }
    }

    throw await _toApiException(
      response,
      decodeFailed ? null : decoded,
      authenticated: sentToken,
    );
  }

  Future<({http.Response response, bool authenticated})> _perform({
    required String method,
    required String path,
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    final Uri uri = Uri.parse(AppConfig.resolve(path, query: query));

    final Map<String, String> headers = <String, String>{
      'Accept': ApiConstants.acceptJson,
    };

    if (body != null) {
      headers['Content-Type'] = ApiConstants.contentTypeJson;
    }

    // Attach the bearer token when one exists. A request without a token is
    // legitimate (a login request, for instance), so a missing token is not an
    // error here — the server decides.
    final String? token = await _tokenStorage.read();
    final bool authenticated = token != null && token.isNotEmpty;
    if (authenticated) {
      headers[ApiConstants.authorizationHeader] =
          '${ApiConstants.bearerPrefix} $token';
    }

    final http.Request request = http.Request(method, uri)
      ..headers.addAll(headers);

    if (body != null) {
      request.body = jsonEncode(body);
    }

    try {
      final http.StreamedResponse streamed = await _httpClient
          .send(request)
          .timeout(_timeout);
      return (
        response: await http.Response.fromStream(streamed),
        authenticated: authenticated,
      );
    } on TimeoutException {
      throw ApiException.network(
        message:
            'The request timed out after ${_timeout.inSeconds}s. '
            'Check that the API is reachable at $baseUrl.',
      );
    } on http.ClientException catch (error) {
      throw ApiException.network(
        message:
            'Could not reach the server. Check your connection and that the '
            'API is running at $baseUrl.',
        cause: error,
      );
    }
  }

  /// Normalises a decoded 2xx body into a shape [ApiEnvelope] accepts.
  ///
  /// Two things are handled here, both of them properties of the wire format
  /// rather than of any one feature:
  ///
  ///  * **A body that is not a JSON object at all** is rejected as a
  ///    [ApiErrorKind.malformedResponse]. A `2xx` carrying a JSON array or a
  ///    bare string is a contract change, and it must surface as a documented
  ///    `ApiException` rather than as a raw cast error.
  ///  * **An absent `data` key is treated as a `null` payload**, but only once
  ///    the body has been confirmed to be an envelope (it carries a boolean
  ///    `success`). Laravel endpoints that return nothing but a message omit
  ///    `data` entirely — `POST /auth/logout` is the one in this app's contract,
  ///    and it answers `{"success": true, "message": "..."}`. That is a valid
  ///    empty payload, not a malformed response.
  ///
  /// A body with no `success` field is passed through untouched so
  /// [ApiEnvelope] still rejects it as not being an envelope at all.
  static Map<String, dynamic> _successBody(Object? decoded) {
    if (decoded is! Map) {
      throw FormatException(
        'A successful API response must be a JSON object, got '
        '${decoded.runtimeType}.',
      );
    }

    final Map<String, dynamic> body = <String, dynamic>{
      ...decoded.cast<String, dynamic>(),
    };
    if (!body.containsKey('data') && body['success'] is bool) {
      body['data'] = null;
    }
    return body;
  }

  Object? _decodeBody(http.Response response) {
    if (response.body.isEmpty) {
      return null;
    }

    try {
      return jsonDecode(response.body);
    } on FormatException catch (error) {
      throw ApiException.malformedResponse(
        message: 'The server returned a response that was not valid JSON.',
        cause: error,
      );
    }
  }

  Future<ApiException> _toApiException(
    http.Response response,
    Object? decoded, {
    required bool authenticated,
  }) async {
    // A revoked or expired token must never be retried, so a `401` clears
    // storage and the rest of the app observes a signed-out state.
    //
    // Clearing is unconditional. `ApiClient` attaches the stored token to every
    // request it makes, so a `401` either means that token is dead or the
    // submitted credentials were rejected — and a token worth keeping survives
    // neither case, so there is nothing to be gained by conditioning it.
    if (response.statusCode == 401) {
      await _tokenStorage.clear();
      return ApiException(
        kind: ApiErrorKind.unauthorized,
        message:
            _messageFrom(decoded) ??
            // Distinguish the two cases for the user: a token that stopped
            // working versus a password that was simply wrong. Laravel
            // normally supplies the message, so this is the fallback.
            (authenticated
                ? 'Your session has ended. Please sign in again.'
                : 'The email or password is incorrect.'),
        statusCode: 401,
        serverMessage: _messageFrom(decoded),
      );
    }

    return switch (response.statusCode) {
      403 => ApiException(
        kind: ApiErrorKind.forbidden,
        message:
            _messageFrom(decoded) ?? 'You do not have permission to do that.',
        statusCode: 403,
        serverMessage: _messageFrom(decoded),
      ),
      404 => ApiException(
        kind: ApiErrorKind.notFound,
        message: _messageFrom(decoded) ?? 'The requested item was not found.',
        statusCode: 404,
        serverMessage: _messageFrom(decoded),
      ),
      409 => ApiException(
        kind: ApiErrorKind.conflict,
        message: _messageFrom(decoded) ?? _defaultConflictMessage,
        statusCode: 409,
        serverMessage: _messageFrom(decoded),
      ),
      422 => ApiException(
        kind: ApiErrorKind.validation,
        message:
            _messageFrom(decoded) ?? 'Please check the highlighted fields.',
        statusCode: 422,
        serverMessage: _messageFrom(decoded),
        validationErrors: _validationErrorsFrom(decoded),
      ),
      429 => ApiException(
        kind: ApiErrorKind.rateLimited,
        message:
            _messageFrom(decoded) ??
            'Too many attempts. Please wait a moment and try again.',
        statusCode: 429,
        serverMessage: _messageFrom(decoded),
      ),
      _ when response.statusCode >= 500 => ApiException(
        kind: ApiErrorKind.server,
        message: _messageFrom(decoded) ?? 'Something went wrong on the server.',
        statusCode: response.statusCode,
        serverMessage: _messageFrom(decoded),
      ),
      _ => ApiException(
        kind: ApiErrorKind.server,
        message: _messageFrom(decoded) ?? 'The request failed.',
        statusCode: response.statusCode,
        serverMessage: _messageFrom(decoded),
      ),
    };
  }

  /// Fallback wording for a `409` that carried no message.
  ///
  /// A `409` always means the request was well-formed but cannot be applied to
  /// the item's current state — a verification that is already in review, a draft
  /// that is already submitted, an active listing that cannot be deleted. The
  /// wording is deliberately neutral so it cannot mislead on any of them, and it
  /// exists because the alternative, "The request failed", is actively wrong: the
  /// user did nothing wrong and retrying identically will not help.
  ///
  /// Every `409` this app's contract produces is raised server-side with an
  /// explicit `abort(409, '...')` message, so this is a last resort rather than
  /// what users normally see.
  static const String _defaultConflictMessage =
      'This action is not possible while the item is in its current state.';

  /// Reads the `message` field from a Laravel error body.  ///
  /// Laravel returns a bare JSON string for `abort(403, '...')`, and
  /// `{ "message": "..." }` for validation and handler-thrown errors. Handle
  /// both.
  static String? _messageFrom(Object? decoded) {
    if (decoded is String && decoded.isNotEmpty) {
      return decoded;
    }
    if (decoded is Map) {
      final Object? message = decoded['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
    }
    return null;
  }

  /// Extracts Laravel's per-field validation messages.
  ///
  /// Laravel returns `errors` as `{ "field": ["message", ...] }`. Values are
  /// normalised to a list so a single string and an array are handled the same
  /// way by the UI.
  static Map<String, List<String>> _validationErrorsFrom(Object? decoded) {
    if (decoded is! Map) {
      return const <String, List<String>>{};
    }

    final Object? errors = decoded['errors'];
    if (errors is! Map) {
      return const <String, List<String>>{};
    }

    return <String, List<String>>{
      for (final MapEntry<Object?, Object?> entry in errors.entries)
        if (entry.key is String)
          entry.key as String: switch (entry.value) {
            String message => <String>[message],
            List<dynamic> messages => messages.whereType<String>().toList(
              growable: false,
            ),
            _ => const <String>[],
          },
    };
  }

  static bool _isSuccessStatus(int statusCode) =>
      statusCode >= 200 && statusCode < 300;
}
