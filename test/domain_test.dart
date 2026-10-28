import 'package:flutter_test/flutter_test.dart';

import 'package:odoo_mobileapp/odoo/domain.dart';

void main() {
  final a = ['a', '=', 1];
  final b = ['b', '=', 2];
  final c = ['c', '=', 3];

  test('normalizeDomain adds implicit ANDs', () {
    expect(normalizeDomain([a, b]), ['&', a, b]);
    expect(normalizeDomain(['|', a, b, c]), ['&', '|', a, b, c]);
    expect(normalizeDomain(['!', a]), ['!', a]);
    expect(normalizeDomain([]), []);
  });

  test('orDomains and andDomains combine normalized domains', () {
    expect(orDomains([
      [a],
      [b, c],
    ]), ['|', a, '&', b, c]);
    expect(andDomains([
      [],
      [a],
      [b],
    ]), ['&', a, b]);
    expect(andDomains([[], []]), []);
  });

  test('parseDomain and parseContext evaluate Python strings', () {
    expect(parseDomain("[('user_id', '=', uid)]", {'uid': 7}), [
      ['user_id', '=', 7],
    ]);
    expect(parseDomain(false, {}), []);
    expect(parseDomain("[('d', '<', context_today())]", {}), isNull);
    expect(parseContext("{'search_default_my': 1}", {}), {'search_default_my': 1});
    expect(parseContext('', {}), {});
  });
}
