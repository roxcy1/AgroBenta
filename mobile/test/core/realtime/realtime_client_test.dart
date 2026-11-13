import 'package:agrobenta_mobile/core/realtime/realtime_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PusherReverbClient.decodeData', () {
    test('decodes the double-encoded JSON string payload', () {
      final Map<String, dynamic> data = PusherReverbClient.decodeData(
        '{"id":5,"body":"hello"}',
      );

      expect(data, <String, dynamic>{'id': 5, 'body': 'hello'});
    });

    test('passes through an already-decoded map', () {
      const Map<String, dynamic> data = <String, dynamic>{'id': 5};

      expect(PusherReverbClient.decodeData(data), same(data));
    });

    test('returns empty for malformed JSON', () {
      expect(PusherReverbClient.decodeData('not-json'), isEmpty);
    });

    test('returns empty for a non-string, non-map value', () {
      expect(PusherReverbClient.decodeData(42), isEmpty);
      expect(PusherReverbClient.decodeData(null), isEmpty);
      expect(PusherReverbClient.decodeData(''), isEmpty);
    });
  });
}
