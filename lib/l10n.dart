import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'l10n_ar.dart';
import 'session_store.dart';

/// The app's language as an Odoo language code (`en_US`, `ar_001`, ...).
///
/// Once signed in it is the user's own Odoo language (`res.users.lang`), so
/// the app matches the web client: records, menus and field labels come
/// translated from Odoo, and the app's own text from [tr].
final appLanguage = ValueNotifier<String>('en_US');

/// Material locale for [appLanguage]; right-to-left languages (Arabic,
/// Hebrew, Persian, ...) flip the layout through it.
Locale get appLocale => Locale(appLanguage.value.split(RegExp('[_-]')).first);

bool get isArabic => appLocale.languageCode == 'ar';

/// Switches the app's language and remembers it for the next start.
Future<void> setAppLanguage(String? code) async {
  if (code == null || code.isEmpty) return;
  appLanguage.value = code;
  await AppPrefs.setLanguage(code);
}

/// The remembered language, else the phone's when it is Arabic.
Future<void> loadAppLanguage() async {
  final saved = await AppPrefs.language();
  final device = PlatformDispatcher.instance.locale.languageCode;
  appLanguage.value = saved ?? (device == 'ar' ? 'ar_001' : 'en_US');
}

/// The app's own text in [appLanguage]. Arabic has a translation; other
/// languages show English, while Odoo's data still comes in the user's
/// language. `{name}` placeholders are filled from [args].
String tr(String text, [Map<String, Object?> args = const {}]) {
  var out = isArabic ? (arabic[text] ?? text) : text;
  for (final e in args.entries) {
    out = out.replaceAll('{${e.key}}', '${e.value}');
  }
  return out;
}
