import 'package:agrobenta_mobile/core/utils/json_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('readString', () {
    test('returns the value', () {
      expect(readString(<String, dynamic>{'name': 'Reyes'}, 'name'), 'Reyes');
    });

    test('throws when the value is not a string', () {
      expect(
        () => readString(<String, dynamic>{'name': 42}, 'name'),
        throwsFormatException,
      );
    });

    test('throws when the key is absent', () {
      expect(
        () => readString(<String, dynamic>{}, 'name'),
        throwsFormatException,
      );
    });
  });

  group('readInt', () {
    test('returns an int', () {
      expect(readInt(<String, dynamic>{'id': 7}, 'id'), 7);
    });

    test('parses a numeric string, as bigint columns may serialise', () {
      expect(readInt(<String, dynamic>{'id': '42'}, 'id'), 42);
    });

    test('throws on a non-numeric string', () {
      expect(
        () => readInt(<String, dynamic>{'id': 'abc'}, 'id'),
        throwsFormatException,
      );
    });
  });

  group('readNullableInt', () {
    test('returns null when absent', () {
      expect(readNullableInt(<String, dynamic>{}, 'quantity'), isNull);
    });

    test('returns null when explicitly null', () {
      expect(
        readNullableInt(<String, dynamic>{'quantity': null}, 'quantity'),
        isNull,
      );
    });
  });

  group('readDecimalString', () {
    test('preserves the exact decimal string from the API', () {
      // asking_price and total_amount are decimal columns serialised as
      // strings. Precision must survive parsing.
      expect(
        readDecimalString(<String, dynamic>{'asking_price': '12500.00'}, 'asking_price'),
        '12500.00',
      );
    });

    test('accepts a JSON number defensively', () {
      expect(
        readDecimalString(<String, dynamic>{'asking_price': 12500}, 'asking_price'),
        '12500',
      );
    });

    test('throws when the value is null', () {
      expect(
        () => readDecimalString(<String, dynamic>{'asking_price': null}, 'asking_price'),
        throwsFormatException,
      );
    });
  });

  group('readDateTime', () {
    test('parses an ISO-8601 timestamp', () {
      final DateTime parsed = readDateTime(
        <String, dynamic>{'created_at': '2026-09-20T12:00:00.000000Z'},
        'created_at',
      );

      expect(parsed.year, 2026);
    });

    test('throws on a malformed timestamp', () {
      expect(
        () => readDateTime(<String, dynamic>{'created_at': '20/09/2026'}, 'created_at'),
        throwsFormatException,
      );
    });
  });

  group('readNullableString', () {
    test('treats an absent key as null', () {
      expect(readNullableString(<String, dynamic>{}, 'gender'), isNull);
    });

    test('returns the value when present', () {
      expect(
        readNullableString(<String, dynamic>{'gender': 'Bull'}, 'gender'),
        'Bull',
      );
    });
  });

  group('readObjectList', () {
    test('returns an empty list when the key is absent', () {
      expect(readObjectList(<String, dynamic>{}, 'listings'), isEmpty);
    });

    test('casts each item to a string-keyed map', () {
      final List<Map<String, dynamic>> result = readObjectList(
        <String, dynamic>{
          'listings': <dynamic>[
            <String, dynamic>{'id': 1},
            <String, dynamic>{'id': 2},
          ],
        },
        'listings',
      );

      expect(result, hasLength(2));
      expect(result.first['id'], 1);
    });

    test('throws when an item is not an object', () {
      expect(
        () => readObjectList(<String, dynamic>{
          'listings': <dynamic>['not-an-object'],
        }, 'listings'),
        throwsFormatException,
      );
    });
  });

  group('readNullableObject', () {
    test('returns null when absent', () {
      expect(
        readNullableObject(<String, dynamic>{}, 'reviewer'),
        isNull,
      );
    });

    test('returns the nested object', () {
      expect(
        readNullableObject(<String, dynamic>{
          'reviewer': <String, dynamic>{'id': 3, 'name': 'Admin'},
        }, 'reviewer'),
        <String, dynamic>{'id': 3, 'name': 'Admin'},
      );
    });
  });
}
