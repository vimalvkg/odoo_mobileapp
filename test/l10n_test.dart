import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_mobileapp/l10n.dart';
import 'package:odoo_mobileapp/l10n_ar.dart';
import 'package:odoo_mobileapp/odoo/format.dart';

void main() {
  tearDown(() => appLanguage.value = 'en_US');

  test('every text passed to tr() has an Arabic translation', () {
    final literal = RegExp(r'''tr\((?:'([^']*)'|"([^"]*)")''');
    final missing = <String>{};
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final m in literal.allMatches(file.readAsStringSync())) {
        final text = m.group(1) ?? m.group(2)!;
        if (!arabic.containsKey(text)) missing.add('$text (${file.path})');
      }
    }
    expect(missing, isEmpty);
  });

  test('translations keep their placeholders', () {
    final placeholder = RegExp(r'\{\w+\}');
    for (final e in arabic.entries) {
      final en = placeholder.allMatches(e.key).map((m) => m[0]).toSet();
      final ar = placeholder.allMatches(e.value).map((m) => m[0]).toSet();
      expect(ar, en, reason: e.key);
    }
  });

  test('follows the Odoo language code', () {
    appLanguage.value = 'ar_001';
    expect(isArabic, isTrue);
    expect(appLocale.languageCode, 'ar');
    expect(tr('Sign out'), 'تسجيل الخروج');
    expect(tr('Archived {name}', {'name': 'S00042'}), 'تمت أرشفة S00042');
    expect(formatDate(DateTime(2026, 10, 28)), '28 أكتوبر 2026');

    // Languages without app translations keep English text.
    appLanguage.value = 'fr_FR';
    expect(isArabic, isFalse);
    expect(tr('Sign out'), 'Sign out');
    expect(formatDate(DateTime(2026, 10, 28)), '28 Oct 2026');
  });
}
