import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:odoo_mobileapp/main.dart';
import 'package:odoo_mobileapp/odoo/rpc.dart';
import 'package:odoo_mobileapp/screens/home_screen.dart';
import 'package:odoo_mobileapp/screens/login_screen.dart';
import 'package:odoo_mobileapp/screens/record_form_screen.dart';
import 'package:odoo_mobileapp/session_store.dart';

final _session = Session(serverUrl: 'https://x', db: 'db', login: 'admin', sessionId: 's');

/// A small Odoo: Discuss + CRM, two overdue and one due activity.
OdooRpc _rpc({bool expired = false}) => OdooRpc(
      _session,
      client: MockClient((req) async {
        final params = (jsonDecode(req.body) as Map)['params'] as Map;
        if (expired) {
          return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'error': {
                  'code': 100,
                  'message': 'Odoo Session Expired',
                  'data': {'name': 'odoo.http.SessionExpiredException', 'message': 'Session expired'},
                },
              }),
              200);
        }
        dynamic result = false;
        if (req.url.path.endsWith('get_session_info')) {
          result = {
            'uid': 2,
            'name': 'Mitchell Admin',
            'user_context': {'lang': 'en_US'},
            'user_companies': {
              'current_company': 1,
              'allowed_companies': {
                '1': {'name': 'Test Co'},
              },
            },
          };
        } else if (req.url.path.endsWith('/web/action/load')) {
          result = {
            'type': 'ir.actions.act_window',
            'res_model': 'crm.lead',
            'views': [
              [false, 'list'],
              [false, 'form'],
            ],
            'context': "{'default_type': 'opportunity'}",
          };
        } else {
          switch (params['method']) {
            case 'load_web_menus':
              result = {
                'root': {'id': 'root', 'children': [1, 2]},
                '1': {'id': 1, 'name': 'Discuss', 'children': [], 'actionID': 10, 'xmlid': 'mail.menu_root_discuss'},
                '2': {'id': 2, 'name': 'CRM', 'children': [], 'actionID': 20, 'xmlid': 'crm.crm_menu_root'},
              };
            case 'search_count':
              final domain = (params['args'] as List).first as List;
              result = params['model'] == 'mail.message' ? 4 : ((domain[1] as List)[1] == '<' ? 2 : 1);
            case 'search_read':
              result = [];
            case 'get_views':
              result = {
                'models': {
                  'crm.lead': {
                    'fields': {
                      'name': {'type': 'char', 'string': 'Opportunity', 'required': true},
                      'display_name': {'type': 'char'},
                    },
                  },
                },
                'views': {
                  'form': {'arch': '<form><sheet><group><field name="name"/></group></sheet></form>'},
                },
              };
            case 'default_get':
              result = {'name': false};
          }
        }
        return http.Response(jsonEncode({'jsonrpc': '2.0', 'result': result}), 200);
      }),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpHome(WidgetTester tester, OdooRpc rpc) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MobileApp(home: HomeScreen(session: _session, rpc: rpc)));
    await _settle(tester);
  }

  testWidgets('home shows the database apps, counters and attention line', (tester) async {
    await pumpHome(tester, _rpc());
    expect(find.text('Good morning, Mitchell').evaluate().isNotEmpty ||
        find.text('Good afternoon, Mitchell').evaluate().isNotEmpty ||
        find.text('Good evening, Mitchell').evaluate().isNotEmpty, isTrue);
    expect(find.text('7 things need your attention'), findsOneWidget); // 2 overdue + 1 today + 4 unread
    expect(find.text('Overdue activities'), findsOneWidget);
    expect(find.text('CRM'), findsOneWidget);
    expect(find.text('Test Co'), findsOneWidget);
  });

  testWidgets('long-press pins an app and quick create opens a new form for it', (tester) async {
    final rpc = _rpc();
    await pumpHome(tester, rpc);

    await tester.longPress(find.text('CRM'));
    await _settle(tester);
    expect(find.text('Pinned'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Quick create'));
    await tester.pumpAndSettle();
    expect(find.text('New in CRM'), findsOneWidget);

    await tester.tap(find.text('New in CRM'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(RecordFormScreen), findsOneWidget);
    expect(find.text('Opportunity *'), findsOneWidget); // empty form in edit mode
  });

  testWidgets('tapping a counter opens My activities', (tester) async {
    await pumpHome(tester, _rpc());
    await tester.tap(find.text('Overdue activities'));
    await _settle(tester);
    expect(find.text('My activities'), findsOneWidget);
  });

  testWidgets('an expired session returns to login with a notice', (tester) async {
    await pumpHome(tester, _rpc(expired: true));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.textContaining('session has ended'), findsOneWidget);
  });
}
