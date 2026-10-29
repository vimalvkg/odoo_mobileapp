import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:odoo_mobileapp/main.dart';
import 'package:odoo_mobileapp/odoo/rpc.dart';
import 'package:odoo_mobileapp/screens/record_form_screen.dart';
import 'package:odoo_mobileapp/screens/record_list_screen.dart';
import 'package:odoo_mobileapp/session_store.dart';

const _fields = {
  'name': {'type': 'char', 'string': 'Name'},
  'display_name': {'type': 'char'},
  'state': {
    'type': 'selection',
    'string': 'Status',
    'selection': [
      ['draft', 'Quotation'],
      ['sale', 'Sales Order'],
    ],
  },
  'amount_total': {'type': 'monetary', 'string': 'Total'},
};

/// Records every call so tests can assert what the app asked Odoo.
class _FakeOdoo {
  final calls = <Map>[];

  OdooRpc rpc() => OdooRpc(
        Session(serverUrl: 'https://x', db: 'db', login: 'a', sessionId: 's'),
        client: MockClient((req) async {
          final params = (jsonDecode(req.body) as Map)['params'] as Map;
          calls.add(params);
          dynamic result = false;
          switch (params['method']) {
            case 'get_views':
              result = {
                'models': {
                  'sale.order': {'fields': _fields},
                },
                'views': {
                  'list': {'arch': '<list><field name="name"/><field name="amount_total"/><field name="state"/></list>'},
                  'search': {
                    'arch': '<search><filter name="quotes" string="Quotations" domain="[(\'state\', \'=\', \'draft\')]"/></search>',
                  },
                  'form': {
                    'arch': '<form><header>'
                        '<button name="action_confirm" type="object" string="Confirm" class="oe_highlight" invisible="state != \'draft\'"/>'
                        '<field name="state" widget="statusbar"/></header>'
                        '<sheet><group><field name="name"/><field name="amount_total"/></group></sheet></form>',
                  },
                },
              };
            case 'search_read':
              result = [
                {'id': 1, 'display_name': 'S001', 'name': 'S001', 'amount_total': 100.0, 'state': 'draft'},
              ];
            case 'search_count':
              result = 1;
            case 'read':
              result = [
                {'id': 1, 'display_name': 'S001', 'name': 'S001', 'amount_total': 100.0, 'state': 'draft'},
              ];
          }
          if (req.url.path.contains('call_button')) result = true;
          return http.Response(jsonEncode({'jsonrpc': '2.0', 'result': result}), 200);
        }),
      );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('a filter chip refetches with its domain', (tester) async {
    final odoo = _FakeOdoo();
    await tester.pumpWidget(MobileApp(
      home: RecordListScreen(
        rpc: odoo.rpc(),
        model: 'sale.order',
        title: 'Orders',
        viewIds: const {'list': null, 'form': null, 'search': null},
      ),
    ));
    await _settle(tester);
    expect(find.text('Quotation'), findsOneWidget); // status pill
    odoo.calls.clear();

    await tester.tap(find.text('Quotations'));
    await tester.pump(const Duration(milliseconds: 500));
    await _settle(tester);

    final search = odoo.calls.firstWhere((c) => c['method'] == 'search_read');
    expect((search['kwargs'] as Map)['domain'], [
      ['state', '=', 'draft'],
    ]);
  });

  testWidgets('the action bar shows the total and runs the primary button', (tester) async {
    final odoo = _FakeOdoo();
    await tester.pumpWidget(MobileApp(
      home: RecordFormScreen(rpc: odoo.rpc(), model: 'sale.order', recordId: 1, title: 'Orders'),
    ));
    await _settle(tester);
    expect(find.text('100.00'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await _settle(tester);
    final call = odoo.calls.firstWhere((c) => c['method'] == 'action_confirm');
    expect(call['args'], [
      [1],
    ]);
  });
}
