import 'package:flutter_test/flutter_test.dart';

import 'package:odoo_mobileapp/odoo/view_arch.dart';
import 'package:odoo_mobileapp/widgets/x2many_lines.dart';

void main() {
  const fields = {
    'product_id': {'type': 'many2one', 'relation': 'product.product', 'string': 'Product'},
    'product_uom_qty': {'type': 'float', 'string': 'Quantity'},
    'price_subtotal': {'type': 'monetary', 'string': 'Subtotal', 'readonly': true},
    'tax_ids': {'type': 'many2many', 'relation': 'account.tax', 'string': 'Taxes'},
    'display_name': {'type': 'char'},
  };

  X2ManyLines lines() => X2ManyLines(
        relation: 'sale.order.line',
        fields: fields,
        columns: parseCardFields(
          '<list><field name="product_id"/><field name="product_uom_qty"/>'
          '<field name="price_subtotal" column_invisible="parent.state == \'draft\'"/></list>',
        ),
        form: null,
        items: [
          LineRecord(id: 7, values: {'id': 7, 'product_id': [3, 'Desk'], 'product_uom_qty': 1.0}, key: 'id-7'),
          LineRecord(id: 8, values: {'id': 8, 'product_id': [4, 'Chair'], 'product_uom_qty': 2.0}, key: 'id-8'),
        ],
      );

  test('no edits produce no commands', () {
    final l = lines();
    expect(l.dirty, isFalse);
    expect(l.commands(), isEmpty);
  });

  test('add, update and remove become Odoo x2many commands', () {
    final l = lines();
    l.items.first.changes['product_uom_qty'] = 5.0;
    l.removed.add(8);
    l.items = [
      l.items.first,
      LineRecord(values: const {}, changes: {'product_id': [9, 'Lamp'], 'product_uom_qty': 3.0, 'tax_ids': [1, 2]}, key: 'new-0'),
    ];
    expect(l.dirty, isTrue);
    expect(l.commands(), [
      [2, 8, 0],
      [1, 7, {'product_uom_qty': 5.0}],
      [
        0,
        0,
        {
          'product_id': 9,
          'product_uom_qty': 3.0,
          'tax_ids': [
            [6, 0, [1, 2]],
          ],
        },
      ],
    ]);
  });

  test('line conditions see the parent record', () {
    final l = lines();
    final subtotal = l.columns.firstWhere((c) => c.name == 'price_subtotal');
    expect(l.columnVisible(subtotal, {'state': 'draft'}), isFalse);
    expect(l.columnVisible(subtotal, {'state': 'sale'}), isTrue);
    expect(l.env(l.items.first, {'state': 'sale'})['product_id'], 3);
    // A new line has no values yet; its unset fields still evaluate.
    expect(l.env(LineRecord(values: const {}, key: 'new-0'), {})['product_uom_qty'], false);
  });
}
