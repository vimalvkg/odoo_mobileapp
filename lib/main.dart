import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_navigation.dart';
import 'l10n.dart';
import 'screens/splash_screen.dart';
import 'theme.dart';

void main() {
  runApp(const MobileApp());
}

class MobileApp extends StatelessWidget {
  final Widget home;

  const MobileApp({super.key, this.home = const SplashScreen()});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([brandColor, themeMode, appLanguage]),
      builder: (_, _) => MaterialApp(
        title: appName,
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light, brandColor.value),
        darkTheme: buildTheme(Brightness.dark, brandColor.value),
        themeMode: themeMode.value,
        locale: appLocale,
        supportedLocales: [for (final code in kMaterialSupportedLanguages) Locale(code)],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: home,
      ),
    );
  }
}
