import 'package:agrobenta_mobile/models/ai_price_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seller_listing_fakes.dart';

void main() {
  test('parses the exact AiPriceEstimateResource shape', () {
    final AiPriceEstimate estimate = AiPriceEstimate.fromJson(
      aiPriceEstimateJson(),
    );

    expect(estimate.listingId, 7);
    expect(estimate.status, 'ok');
    expect(estimate.estimatedMin, isNull);
    expect(estimate.estimatedMax, isNull);
    expect(estimate.estimatedValue, '9798.00');
    expect(estimate.basis, contains('Prototype CatBoost'));
    expect(estimate.modelVersion, 'v3-targeted');
    expect(estimate.provenance, 'synthetic');
    expect(estimate.inputSnapshot['livestock_type'], 'chicken');
    expect(estimate.warnings, isEmpty);
  });

  test('recognises a warning estimate but still keeps its value', () {
    final AiPriceEstimate estimate = AiPriceEstimate.fromJson(
      aiPriceEstimateJson(
        status: 'warning',
        warnings: <String>['Outside the typical range.'],
        reasonCodes: <String>['outside_typical_age_weight'],
      ),
    );

    expect(estimate.isWarning, isTrue);
    expect(estimate.estimatedValue, '9798.00');
    expect(estimate.warnings, <String>['Outside the typical range.']);
    expect(estimate.reasonCodes, <String>['outside_typical_age_weight']);
  });

  test('rejects a non-usable status instead of treating it as a price', () {
    expect(
      () => AiPriceEstimate.fromJson(aiPriceEstimateJson(status: 'withheld')),
      throwsFormatException,
    );
  });
}
