import 'package:flutter/material.dart';

import '../session_store.dart';
import '../theme.dart';
import '../widgets/brand_mark.dart';
import 'login_screen.dart';
import 'home_screen.dart';

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
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => session == null ? const LoginScreen() : HomeScreen(session: session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [brandColor, Color.lerp(brandColor, Colors.black, 0.35)!],
          ),
        ),
        child: const Center(child: BrandMark(size: 80)),
      ),
    );
  }
}
