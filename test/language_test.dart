import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:odoo_mobileapp/l10n.dart';
import 'package:odoo_mobileapp/main.dart';
import 'package:odoo_mobileapp/odoo/rpc.dart';
import 'package:odoo_mobileapp/screens/home_screen.dart';
import 'package:odoo_mobileapp/session_store.dart';

final _session = Session(serverUrl: 'https://x', db: 'db', login: 'admin', sessionId: 's');

/// A user whose Odoo language is [lang]; `res.users.write` changes it.
class _FakeOdoo {
  String lang;
  final writes = <Map>[];

  _FakeOdoo(this.lang);

  OdooRpc rpc() => OdooRpc(
        _session,
        client: MockClient((req) async {
          final params = (jsonDecode(req.body) as Map)['params'] as Map;
          dynamic result = false;
          if (req.url.path.endsWith('get_session_info')) {
            result = {
              'uid': 2,
              'name': 'Mitchell Admin',
              'user_context': {'lang': lang},
              'user_companies': {
                'current_company': 1,
                'allowed_companies': {
                  '1': {'name': 'Test Co'},
                },
              },
            };
          } else if (params['model'] == 'res.lang') {
            result = [
              {'id': 1, 'code': 'en_US', 'name': 'English (US)'},
              {'id': 2, 'code': 'ar_001', 'name': 'Arabic / الْعَرَبيّة'},
            ];
          } else if (params['model'] == 'res.users' && params['method'] == 'write') {
            final vals = (params['args'] as List)[1] as Map;
            writes.add(vals);
            lang = vals['lang'] as String;
            result = true;
          } else if (params['method'] == 'load_web_menus') {
            result = {
              'root': {'id': 'root', 'children': [1]},
              '1': {'id': 1, 'name': 'CRM', 'children': [], 'actionID': 20, 'xmlid': 'crm.crm_menu_root'},
            };
          } else if (params['method'] == 'search_read') {
            result = [];
          }
          return http.Response(jsonEncode({'jsonrpc': '2.0', 'result': result}), 200,
              headers: {'content-type': 'application/json'});
        }),
      );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appLanguage.value = 'en_US';
  });
  tearDown(() => appLanguage.value = 'en_US');

  testWidgets('a user whose Odoo language is Arabic gets the app in Arabic, right to left', (tester) async {
    final odoo = _FakeOdoo('ar_001');
    await tester.pumpWidget(MobileApp(home: HomeScreen(session: _session, rpc: odoo.rpc())));
    await _settle(tester);

    expect(appLanguage.value, 'ar_001');
    expect(find.text('التطبيقات'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('التطبيقات'))), TextDirection.rtl);
    expect(await AppPrefs.language(), 'ar_001');
  });

  testWidgets('picking a language in Profile saves it in Odoo and switches the app', (tester) async {
    final odoo = _FakeOdoo('en_US');
    await tester.pumpWidget(MobileApp(home: HomeScreen(session: _session, rpc: odoo.rpc())));
    await _settle(tester);
    expect(find.text('Apps'), findsOneWidget);

    await tester.tap(find.text('Profile').last);
    await _settle(tester);
    await tester.tap(find.text('Language'));
    await _settle(tester);
    await tester.tap(find.text('Arabic / الْعَرَبيّة'));
    await _settle(tester);

    expect(odoo.writes, [
      {'lang': 'ar_001'},
    ]);
    expect(appLanguage.value, 'ar_001');
    // Back on a fresh home screen, now in Arabic.
    expect(find.text('التطبيقات'), findsOneWidget);
    expect(find.text('الرئيسية'), findsOneWidget);
  });
}
