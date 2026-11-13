import '../core/utils/json_utils.dart';

/// The usable outcomes of a price-suggestion request.
///
/// `ok` and `warning` carry a point estimate. The remaining outcomes deliberately
/// carry none: the server withheld the prediction, could not be reached, or
/// rejected the inputs. Keeping them as distinct outcomes stops the UI from
/// rendering a missing value as if it were a price.
enum PriceSuggestionOutcome {
  ok,
  warning,
  withheld,
  unavailable,
  invalid,
  error,
}

/// One stored price estimate from `AiPriceEstimateResource`.
///
/// This mirrors the success payload exactly. The provider is point-only today,
/// so [estimatedMin] and [estimatedMax] are nullable and are not invented here.
class AiPriceEstimate {
  const AiPriceEstimate({
    required this.listingId,
    required this.estimatedMin,
    required this.estimatedMax,
    required this.estimatedValue,
    required this.basis,
    required this.inputSnapshot,
    required this.estimatedAt,
    required this.status,
    required this.warnings,
    required this.reasonCodes,
    required this.provenance,
    required this.modelVersion,
  });

  factory AiPriceEstimate.fromJson(Map<String, dynamic> json) {
    final String status = readString(json, 'status');
    if (status != 'ok' && status != 'warning') {
      throw FormatException(
        'Expected a usable price-suggestion status, got "$status".',
      );
    }

    return AiPriceEstimate(
      listingId: readInt(json, 'listing_id'),
      estimatedMin: readNullableDecimalString(json, 'estimated_min'),
      estimatedMax: readNullableDecimalString(json, 'estimated_max'),
      estimatedValue: readDecimalString(json, 'estimated_value'),
      basis: readString(json, 'basis'),
      inputSnapshot:
          readNullableObject(json, 'input_snapshot') ??
          const <String, dynamic>{},
      estimatedAt: readNullableDateTime(json, 'estimated_at'),
      status: status,
      warnings: readStringList(json, 'warnings'),
      reasonCodes: readStringList(json, 'reason_codes'),
      provenance: readNullableString(json, 'provenance'),
      modelVersion: readNullableString(json, 'model_version'),
    );
  }

  /// `listings.id` this estimate belongs to.
  final int listingId;

  /// The optional range floor. Null with the current point-only provider.
  final String? estimatedMin;

  /// The optional range ceiling. Null with the current point-only provider.
  final String? estimatedMax;

  /// The point estimate as the API serialises it, e.g. `"9798.00"`.
  final String estimatedValue;

  /// The server's explanation of how the estimate was produced.
  final String basis;

  /// The model inputs captured when the estimate was produced.
  final Map<String, dynamic> inputSnapshot;

  final DateTime? estimatedAt;

  /// `ok` or `warning`.
  final String status;

  /// Provider warnings. A warning estimate still carries a usable value.
  final List<String> warnings;

  /// Stable provider reason codes, e.g. `outside_typical_age_weight`.
  final List<String> reasonCodes;

  /// `synthetic` for the current prototype model.
  final String? provenance;

  /// The serving model version, e.g. `v3-targeted`.
  final String? modelVersion;

  bool get isWarning => status == 'warning';

  @override
  String toString() =>
      'AiPriceEstimate($listingId, $status, $estimatedValue, $modelVersion)';
}

/// The full result of one price-suggestion attempt.
///
/// A success stores the parsed [estimate]. A refusal stores the server's
/// structured reason code and warnings, so the UI can explain what happened
/// without inventing a price or a confidence score.
class PriceSuggestionResult {
  const PriceSuggestionResult({
    required this.outcome,
    required this.message,
    this.estimate,
    this.warnings = const <String>[],
    this.reasonCodes = const <String>[],
  });

  final PriceSuggestionOutcome outcome;

  /// A displayable summary from the server or transport layer.
  final String message;

  /// Present only for [PriceSuggestionOutcome.ok] and
  /// [PriceSuggestionOutcome.warning].
  final AiPriceEstimate? estimate;

  final List<String> warnings;

  final List<String> reasonCodes;

  bool get hasEstimate => estimate != null;

  bool get canRetry =>
      outcome == PriceSuggestionOutcome.unavailable ||
      outcome == PriceSuggestionOutcome.error;

  /// The most specific text to show. Warnings from the server explain a refusal
  /// more precisely than the generic envelope message.
  String get displayMessage => warnings.isNotEmpty ? warnings.first : message;

  @override
  String toString() => 'PriceSuggestionResult(${outcome.name}, $message)';
}
