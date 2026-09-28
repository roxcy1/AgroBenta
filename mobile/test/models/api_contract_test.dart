import 'package:agrobenta_mobile/models/api_envelope.dart';
import 'package:agrobenta_mobile/models/pagination.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiEnvelope', () {
    test('parses the Laravel envelope shape', () {
      final ApiEnvelope<Map<String, dynamic>> envelope =
          ApiEnvelope<Map<String, dynamic>>.fromJson(
            <String, dynamic>{
              'success': true,
              'message': 'Logged in successfully.',
              'data': <String, dynamic>{'id': 1},
            },
            (Object? data) => data! as Map<String, dynamic>,
          );

      expect(envelope.success, isTrue);
      expect(envelope.message, 'Logged in successfully.');
      expect(envelope.data['id'], 1);
    });

    test('accepts a null message, as returned by some read endpoints', () {
      final ApiEnvelope<Object?> envelope = ApiEnvelope<Object?>.fromJson(
        <String, dynamic>{
          'success': true,
          'data': <String, dynamic>{'id': 1},
        },
        (Object? data) => data,
      );

      expect(envelope.message, isNull);
    });

    test('throws when success is missing', () {
      expect(
        () => ApiEnvelope<Object?>.fromJson(
          <String, dynamic>{'data': null},
          (Object? data) => data,
        ),
        throwsFormatException,
      );
    });

    test('throws when data is missing', () {
      expect(
        () => ApiEnvelope<Object?>.fromJson(
          <String, dynamic>{'success': true},
          (Object? data) => data,
        ),
        throwsFormatException,
      );
    });

    test('throws when message is not a string', () {
      expect(
        () => ApiEnvelope<Object?>.fromJson(
          <String, dynamic>{'success': true, 'message': 5, 'data': null},
          (Object? data) => data,
        ),
        throwsFormatException,
      );
    });
  });

  group('Pagination', () {
    // Shape taken verbatim from the nested `pagination` object that
    // backend/app/Http/Controllers/Api/Admin/ListingController.php returns.
    final Map<String, dynamic> json = <String, dynamic>{
      'current_page': 2,
      'last_page': 5,
      'per_page': 15,
      'total': 68,
    };

    test('parses the hand-rolled pagination object', () {
      final Pagination pagination = Pagination.fromJson(json);

      expect(pagination.currentPage, 2);
      expect(pagination.lastPage, 5);
      expect(pagination.perPage, 15);
      expect(pagination.total, 68);
    });

    test('derives page navigation flags', () {
      final Pagination pagination = Pagination.fromJson(json);

      expect(pagination.hasPreviousPage, isTrue);
      expect(pagination.hasNextPage, isTrue);
    });

    test('reports no next page on the last page', () {
      final Pagination pagination = Pagination.fromJson(
        <String, dynamic>{
          'current_page': 5,
          'last_page': 5,
          'per_page': 15,
          'total': 68,
        },
      );

      expect(pagination.hasNextPage, isFalse);
      expect(pagination.hasPreviousPage, isTrue);
    });

    test('reports a single page when there are no records', () {
      final Pagination pagination = Pagination.fromJson(
        <String, dynamic>{
          'current_page': 1,
          'last_page': 1,
          'per_page': 15,
          'total': 0,
        },
      );

      expect(pagination.hasPreviousPage, isFalse);
      expect(pagination.hasNextPage, isFalse);
    });

    test('converts to a zero-based index for the Laravel page parameter', () {
      expect(Pagination.fromJson(json).laravelPageIndex, 1);
      expect(
        Pagination.fromJson(<String, dynamic>{
          'current_page': 1,
          'last_page': 1,
          'per_page': 15,
          'total': 0,
        }).laravelPageIndex,
        0,
      );
    });

    test('throws when a field is missing', () {
      expect(
        () => Pagination.fromJson(<String, dynamic>{'current_page': 1}),
        throwsFormatException,
      );
    });
  });
}
