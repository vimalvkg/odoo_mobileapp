import 'package:flutter_test/flutter_test.dart';

import 'package:tailorline_mobile/odoo/format.dart';
import 'package:tailorline_mobile/odoo/menus.dart';

void main() {
  test('parseMenus builds the app tree from load_web_menus', () {
    final apps = parseMenus({
      'root': {'id': 'root', 'name': 'root', 'children': [1, 5]},
      '1': {'id': 1, 'name': 'Sales', 'children': [2, 3], 'actionID': false, 'webIcon': 'sale,static/description/icon.svg'},
      '2': {'id': 2, 'name': 'Orders', 'children': [4], 'actionID': false},
      '3': {'id': 3, 'name': 'Customers', 'children': [], 'actionID': 30},
      '4': {'id': 4, 'name': 'Quotations', 'children': [], 'actionID': 40},
      '5': {'id': 5, 'name': 'Discuss', 'children': [], 'actionID': 50},
    });
    expect(apps.map((a) => a.name), ['Sales', 'Discuss']);
    expect(apps[0].firstAction?.name, 'Quotations');
    expect(apps[1].firstAction?.id, 5);
    expect(apps[0].actionsWithPath().map((e) => e.$2), ['Sales / Orders / Quotations', 'Sales / Customers']);
  });

  group('formatFieldValue', () {
    test('formats common field types', () {
      expect(formatFieldValue([3, 'Azure Interior'], {'type': 'many2one'}), 'Azure Interior');
      expect(formatFieldValue('sale', {
        'type': 'selection',
        'selection': [
          ['draft', 'Quotation'],
          ['sale', 'Sales Order'],
        ],
      }), 'Sales Order');
      expect(formatFieldValue(1234567.5, {'type': 'monetary'}), '1,234,567.50');
      expect(formatFieldValue(-999, {'type': 'monetary'}), '-999.00');
      expect(formatFieldValue('2026-10-28', {'type': 'date'}), '28 Oct 2026');
      expect(formatFieldValue(false, {'type': 'char'}), '');
      expect(formatFieldValue(false, {'type': 'boolean'}), 'No');
      expect(formatFieldValue([1, 2, 3], {'type': 'many2many'}), '3 records');
      expect(formatFieldValue('<p>Hello&nbsp;<b>there</b></p>', {'type': 'html'}), 'Hello there');
    });

    test('datetimes round-trip through UTC', () {
      final local = DateTime(2026, 10, 28, 14, 5);
      final serialized = serializeOdooDateTime(local);
      expect(parseOdooDateTime(serialized), local);
    });
  });
}
