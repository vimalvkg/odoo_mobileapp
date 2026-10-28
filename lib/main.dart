import 'package:flutter/material.dart';

import 'app_navigation.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const TailorlineApp());
}

class TailorlineApp extends StatelessWidget {
  const TailorlineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tailorline',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF185FA5)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        cardTheme: const CardThemeData(elevation: 0.5),
      ),
      home: const SplashScreen(),
    );
  }
}
