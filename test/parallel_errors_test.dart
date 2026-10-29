import 'package:flutter_test/flutter_test.dart';

import 'package:odoo_mobileapp/odoo/rpc.dart';

void main() {
  test('both returns both results', () async {
    expect(await (Future.value(1), Future.value('a')).both, (1, 'a'));
  });

  test('both rethrows the OdooException itself, not a ParallelWaitError', () async {
    final failing = Future<int>.error(const OdooException('Session expired', name: 'odoo.http.SessionExpiredException'));
    await expectLater(
      (failing, Future.value(2)).both,
      throwsA(isA<OdooException>().having((e) => e.isSessionExpired, 'isSessionExpired', isTrue)),
    );
  });
}
