import 'package:flutter/material.dart';

import '../biometric.dart';
import '../session_store.dart';
import '../theme.dart';
import '../widgets/brand_mark.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'lock_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _resume();
  }

  Future<void> _resume() async {
    final session = await SessionStore.load();
    final mode = await AppPrefs.themeMode();
    themeMode.value = ThemeMode.values.where((m) => m.name == mode).firstOrNull ?? ThemeMode.system;
    final Widget next;
    if (session == null) {
      next = const LoginScreen();
    } else {
      // Start in the company's colours remembered from the last session.
      final color = await AppPrefs.brandColor(session.serverUrl, session.db);
      if (color != null) brandColor.value = Color(color);
      next = await AppPrefs.biometricEnabled() && await biometricAvailable()
          ? LockScreen(session: session)
          : HomeScreen(session: session);
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => next));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [brandOf(context), Color.lerp(brandOf(context), Colors.black, 0.35)!],
          ),
        ),
        child: const Center(child: BrandMark(size: 80)),
      ),
    );
  }
}
