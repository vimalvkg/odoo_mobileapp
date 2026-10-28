import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:odoo_mobileapp/odoo/rpc.dart';
import 'package:odoo_mobileapp/screens/record_form_screen.dart';
import 'package:odoo_mobileapp/session_store.dart';

const _orderArch = '''<form><sheet><group><field name="partner_id"/></group>
<notebook><page string="Order Lines"><field name="order_line"><list>
<field name="display_type" column_invisible="True"/>
<field name="product_id" required="not display_type"/>
<field name="product_uom_qty"/><field name="price_subtotal"/>
</list></field></page></notebook></sheet></form>''';

void main() {
  testWidgets('adding an order line saves an Odoo create command', (tester) async {
    final writes = <List<dynamic>>[];
    final client = MockClient((req) async {
      final params = (jsonDecode(req.body) as Map)['params'] as Map;
      dynamic result;
      switch (params['method']) {
        case 'get_views':
          result = {
            'models': {
              'sale.order': {
                'fields': {
                  'display_name': {'type': 'char'},
                  'partner_id': {'type': 'many2one', 'relation': 'res.partner', 'string': 'Customer'},
                  'order_line': {'type': 'one2many', 'relation': 'sale.order.line', 'string': 'Order Lines'},
                },
              },
              'sale.order.line': {
                'fields': {
                  'display_name': {'type': 'char'},
                  'display_type': {'type': 'selection', 'selection': []},
                  'product_id': {'type': 'many2one', 'relation': 'product.product', 'string': 'Product'},
                  'product_uom_qty': {'type': 'float', 'string': 'Quantity'},
                  'price_subtotal': {'type': 'monetary', 'string': 'Amount', 'readonly': true},
                },
              },
            },
            'views': {
              'form': {'arch': _orderArch},
            },
          };
        case 'read':
          result = params['model'] == 'sale.order'
              ? [
                  {'id': 5, 'display_name': 'S00005', 'partner_id': [1, 'Azure'], 'order_line': []},
                ]
              : [];
        case 'search_read':
          result = [
            {'id': 42, 'display_name': 'Desk Lamp'},
          ];
        case 'write':
          writes.add(params['args'] as List);
          result = true;
        default:
          result = false;
      }
      return http.Response(jsonEncode({'jsonrpc': '2.0', 'result': result}), 200);
    });
    final rpc = OdooRpc(Session(serverUrl: 'https://x', db: 'd', login: 'a', sessionId: 's'), client: client);

    await tester.pumpWidget(MaterialApp(home: RecordFormScreen(rpc: rpc, model: 'sale.order', recordId: 5, title: 'Orders')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.text('Order Lines'), findsOneWidget); // tab title only, no duplicate label
    await tester.tap(find.text('Add a line'));
    await tester.pumpAndSettle();
    expect(find.text('Product *'), findsOneWidget); // required="not display_type" on a new line

    await tester.tap(find.ancestor(of: find.text('Product *'), matching: find.byType(InkWell)).first);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desk Lamp'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Quantity'), '3');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Desk Lamp'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(writes, [
      [
        [5],
        {
          'order_line': [
            [0, 0, {'product_id': 42, 'product_uom_qty': 3.0}],
          ],
        },
      ],
    ]);
  });
}
