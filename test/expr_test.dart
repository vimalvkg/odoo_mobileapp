import 'package:flutter_test/flutter_test.dart';

import 'package:odoo_mobileapp/odoo/expr.dart';

void main() {
  group('evalPy', () {
    test('literals and containers', () {
      expect(evalPy("[('state', '=', 'draft'), ('id', 'in', [1, 2])]"), [
        ['state', '=', 'draft'],
        ['id', 'in', [1, 2]],
      ]);
      expect(evalPy("{'default_type': 'out_invoice', 'x': True, 'n': None}"),
          {'default_type': 'out_invoice', 'x': true, 'n': null});
      expect(evalPy('-1.5'), -1.5);
      expect(evalPy('()'), []);
    });

    test('names, comparisons and boolean logic', () {
      final env = {'state': 'sale', 'amount': 10, 'partner_id': false, 'uid': 2};
      expect(evalPy("state != 'draft'", env), isTrue);
      expect(evalPy("state in ('draft', 'sent')", env), isFalse);
      expect(evalPy("state not in ['draft', 'sent']", env), isTrue);
      expect(evalPy('not partner_id', env), isTrue);
      expect(evalPy('amount > 5 and amount <= 10', env), isTrue);
      expect(evalPy('partner_id or uid', env), 2);
      expect(evalPy("[('user_id', '=', uid)]", env), [
        ['user_id', '=', 2],
      ]);
    });

    test('short-circuits like Python', () {
      expect(evalPy("x and x.get('a')", {'x': false}), isFalse);
      expect(evalPy("context.get('k', 'd')", {'context': <String, dynamic>{}}), 'd');
      expect(evalPy("'a' if flag else 'b'", {'flag': false}), 'b');
    });

    test('unsupported Python throws ExprError', () {
      expect(() => evalPy("[('date', '<', context_today().strftime('%Y-%m-%d'))]"), throwsA(isA<ExprError>()));
      expect(() => evalPy('unknown_name'), throwsA(isA<ExprError>()));
      expect(() => evalPy("'open"), throwsA(isA<ExprError>()));
    });
  });

  test('evalModifier treats unknown expressions as false', () {
    expect(evalModifier("state == 'done'", {'state': 'done'}), isTrue);
    expect(evalModifier('1', {}), isTrue);
    expect(evalModifier(null, {}), isFalse);
    expect(evalModifier('some_missing_field', {}), isFalse);
  });
}
