import 'package:flutter_test/flutter_test.dart';

import 'package:tailorline_mobile/odoo_client.dart';

void main() {
  group('normalizeServerUrl', () {
    test('adds https for public hosts and http for LAN hosts', () {
      expect(normalizeServerUrl('shop.example.com'), 'https://shop.example.com');
      expect(normalizeServerUrl('192.168.1.20:8069'), 'http://192.168.1.20:8069');
      expect(normalizeServerUrl('localhost:8069'), 'http://localhost:8069');
    });

    test('keeps an explicit scheme and strips the trailing slash', () {
      expect(normalizeServerUrl(' http://shop.example.com/ '), 'http://shop.example.com');
    });
  });

  group('extractSessionId', () {
    test('reads session_id from a single cookie', () {
      expect(extractSessionId('session_id=abc123; Expires=Wed, 01 Jan 2027 00:00:00 GMT; Path=/'), 'abc123');
    });

    test('reads session_id when several cookies are comma-joined', () {
      expect(extractSessionId('frontend_lang=en_US; Path=/,session_id=xyz; HttpOnly; Path=/'), 'xyz');
    });

    test('returns null when absent or empty', () {
      expect(extractSessionId(null), isNull);
      expect(extractSessionId('frontend_lang=en_US; Path=/'), isNull);
      expect(extractSessionId('session_id=; Path=/'), isNull);
    });
  });
}
