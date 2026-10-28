import 'package:agrobenta_mobile/features/seller_listings/state/seller_listing_draft.dart';
import 'package:agrobenta_mobile/features/seller_listings/view/seller_listing_input_formatters.dart';
import 'package:agrobenta_mobile/features/seller_listings/view/seller_listing_validators.dart';
import 'package:agrobenta_mobile/models/listing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/seller_listing_fakes.dart';

void main() {
  group('validateAgeValue', () {
    test('is optional', () {
      expect(validateAgeValue(''), isNull);
      expect(validateAgeValue(null), isNull);
    });

    test('accepts a whole number below every limit', () {
      expect(validateAgeValue('18', unit: 'year'), isNull);
      expect(validateAgeValue('18', unit: 'month'), isNull);
      expect(validateAgeValue('18', unit: 'day'), isNull);
    });

    test('rejects a fractional or negative age', () {
      expect(validateAgeValue('18.5', unit: 'month'), isNotNull);
      expect(validateAgeValue('-1', unit: 'month'), isNotNull);
      expect(validateAgeValue('eighteen', unit: 'month'), isNotNull);
    });

    test('caps the value at 25 years', () {
      expect(validateAgeValue('25', unit: 'year'), isNull);
      expect(validateAgeValue('26', unit: 'year'), isNotNull);
    });

    test('caps the value at 300 months', () {
      expect(validateAgeValue('300', unit: 'month'), isNull);
      expect(validateAgeValue('301', unit: 'month'), isNotNull);
    });

    test('caps the value at 9,125 days', () {
      expect(validateAgeValue('9125', unit: 'day'), isNull);
      expect(validateAgeValue('9126', unit: 'day'), isNotNull);
    });

    test('applies the limit in the selected unit, with no conversion', () {
      // The same number is valid in months and invalid in years.
      expect(validateAgeValue('300', unit: 'month'), isNull);
      expect(validateAgeValue('300', unit: 'year'), isNotNull);
      expect(validateAgeValue('9125', unit: 'day'), isNull);
      expect(validateAgeValue('9125', unit: 'year'), isNotNull);
    });

    test('cannot bound the value without a unit', () {
      expect(validateAgeValue('99999'), isNull);
      expect(maxAgeForUnit(null), isNull);
    });

    test('exposes the per-unit limits', () {
      expect(maxAgeForUnit('day'), 9125);
      expect(maxAgeForUnit('month'), 300);
      expect(maxAgeForUnit('year'), 25);
    });
  });

  group('validateWeightValue', () {
    test('is optional', () {
      expect(validateWeightValue(''), isNull);
    });

    test('accepts up to two decimal places', () {
      expect(validateWeightValue('320'), isNull);
      expect(validateWeightValue('320.5'), isNull);
      expect(validateWeightValue('320.50'), isNull);
    });

    test('rejects a third decimal place', () {
      expect(validateWeightValue('320.505'), isNotNull);
    });

    test('rejects separators, symbols and junk', () {
      expect(validateWeightValue('1,320'), isNotNull);
      expect(validateWeightValue('320kg'), isNotNull);
      expect(validateWeightValue('3.2.1'), isNotNull);
      expect(validateWeightValue('320.'), isNotNull);
    });

    test('rejects a negative weight', () {
      expect(validateWeightValue('-1'), isNotNull);
    });
  });

  group('validateAskingPrice', () {
    test('is required', () {
      expect(validateAskingPrice(''), isNotNull);
    });

    test('accepts up to two decimal places', () {
      expect(validateAskingPrice('42500'), isNull);
      expect(validateAskingPrice('42500.5'), isNull);
      expect(validateAskingPrice('42500.50'), isNull);
    });

    test('rejects a third decimal place rather than rounding it', () {
      expect(validateAskingPrice('42500.001'), isNotNull);
    });

    test('rejects a currency symbol, separator or exponent', () {
      expect(validateAskingPrice('₱42500'), isNotNull);
      expect(validateAskingPrice('42,500'), isNotNull);
      expect(validateAskingPrice('4.25e4'), isNotNull);
    });
  });

  group('DigitsOnlyInputFormatter', () {
    const DigitsOnlyInputFormatter formatter = DigitsOnlyInputFormatter();

    TextEditingValue apply(String oldText, String newText) =>
        formatter.formatEditUpdate(
          TextEditingValue(text: oldText),
          TextEditingValue(text: newText),
        );

    test('accepts digits and an empty field', () {
      expect(apply('12', '123').text, '123');
      expect(apply('12', '').text, '');
    });

    test('rejects an edit containing a non-digit instead of stripping it', () {
      expect(apply('12', '12a').text, '12');
      expect(apply('1', '1 2').text, '1');
      expect(apply('1', '1.5').text, '1');
    });

    test('rejects a paste that is not all digits', () {
      expect(apply('', '18 months').text, '');
    });
  });

  group('DecimalInputFormatter', () {
    const DecimalInputFormatter formatter = DecimalInputFormatter();

    TextEditingValue apply(String oldText, String newText) =>
        formatter.formatEditUpdate(
          TextEditingValue(text: oldText),
          TextEditingValue(text: newText),
        );

    test('accepts whole numbers, one or two decimals, and a trailing point', () {
      expect(apply('', '42500').text, '42500');
      expect(apply('42500', '42500.5').text, '42500.5');
      expect(apply('42500.5', '42500.50').text, '42500.50');
      expect(apply('42500', '42500.').text, '42500.');
      expect(apply('42500.50', '').text, '');
    });

    test('rejects a third decimal instead of truncating it', () {
      expect(apply('42500.12', '42500.123').text, '42500.12');
      expect(apply('', '320.505').text, '');
    });

    test('rejects a paste with a separator, symbol or letters', () {
      expect(apply('', '42,500').text, '');
      expect(apply('', '₱42500').text, '');
      expect(apply('', '42500php').text, '');
    });

    test('rejects a second decimal point or a leading point', () {
      expect(apply('1.2', '1.2.3').text, '1.2');
      expect(apply('', '.5').text, '');
    });
  });

  group('SellerListingDraft', () {
    test('trims a whole decimal off the age prefilled from the API', () {
      final Listing listing = Listing.fromJson(listingJson());
      expect(listing.ageValue, '18.0');

      final SellerListingDraft draft = SellerListingDraft.fromListing(listing);
      expect(draft.ageValue, '18');
      expect(draft.toRequestBody()['age_value'], 18);
    });

    test('leaves a fractional age intact so the validators can reject it', () {
      final Listing listing = Listing.fromJson(listingJson(ageValue: '18.5'));
      final SellerListingDraft draft = SellerListingDraft.fromListing(listing);
      expect(draft.ageValue, '18.5');
    });

    test('omits an unparseable age or quantity instead of throwing', () {
      const SellerListingDraft draft = SellerListingDraft(
        livestockType: 'Cattle',
        ageValue: 'eighteen',
        ageUnit: 'month',
        quantity: 'four',
        askingPrice: '42500',
        location: 'Trinidad',
      );

      final Map<String, dynamic> body = draft.toRequestBody();
      expect(body.containsKey('age_value'), isFalse);
      expect(body.containsKey('quantity'), isFalse);
      expect(body['asking_price'], '42500');
    });
  });
}
