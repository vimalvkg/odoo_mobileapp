import 'package:flutter/material.dart';

import '../app_navigation.dart';
import '../biometric.dart';
import '../l10n.dart';
import '../odoo_client.dart';
import '../session_store.dart';
import '../theme.dart';
import '../widgets/brand_mark.dart';
import 'home_screen.dart';

/// Shown on launch when biometric unlock is on: the saved session is only
/// resumed after the phone confirms it's the owner.
class LockScreen extends StatefulWidget {
  final Session session;

  const LockScreen({super.key, required this.session});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    final ok = await biometricUnlock(tr('Unlock to continue'));
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(session: widget.session)));
    } else {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [brand, Color.lerp(brand, Colors.black, 0.35)!],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              BrandMark(
                size: 72,
                logoUrl: OdooClient.publicLogoUrl(widget.session.serverUrl, widget.session.db),
              ),
              const SizedBox(height: 20),
              Text(
                widget.session.login,
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: brand),
                onPressed: _unlock,
                icon: const Icon(Icons.fingerprint),
                label: Text(_failed ? tr('Try again') : tr('Unlock')),
              ),
              TextButton(
                onPressed: () => endSession(),
                child: Text(tr('Sign in with password'), style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
