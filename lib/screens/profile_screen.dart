import 'package:flutter/material.dart';

import '../app_navigation.dart';
import '../biometric.dart';
import '../odoo/rpc.dart';
import '../session_store.dart';
import '../theme.dart';
import '../widgets/record_avatar.dart';
import 'webview_screen.dart';

/// The signed-in user, their company and server, and app settings.
class ProfileScreen extends StatefulWidget {
  final OdooRpc rpc;

  const ProfileScreen({super.key, required this.rpc});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _biometricAvailable = false;
  bool _biometricOn = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final available = await biometricAvailable();
    final on = await AppPrefs.biometricEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricOn = on;
      });
    }
  }

  Future<void> _toggleBiometric(bool on) async {
    // Confirm it's the owner before turning it on, so it can't be enabled
    // on someone else's phone that happens to be unlocked.
    if (on && !await biometricUnlock('Confirm to enable quick unlock')) return;
    await AppPrefs.setBiometricEnabled(on);
    if (mounted) setState(() => _biometricOn = on);
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    await AppPrefs.setThemeMode(mode.name);
  }

  Widget _section(String title, List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: scheme.outline),
            ),
          ),
          Card(child: Column(children: children)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rpc = widget.rpc;
    final session = rpc.session;
    final scheme = Theme.of(context).colorScheme;
    final name = rpc.userName ?? session.login;
    final logo = rpc.companyLogoUrl;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: Text('Profile', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      RecordAvatar(
                        rpc: rpc,
                        model: 'res.users',
                        id: rpc.uid,
                        imageField: 'avatar_128',
                        text: name,
                        size: 84,
                      ),
                      const SizedBox(height: 12),
                      Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(session.login, style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
            _section('Company', [
              ListTile(
                leading: logo == null
                    ? const Icon(Icons.business_outlined)
                    : SizedBox(
                        width: 40,
                        height: 40,
                        child: Image.network(
                          logo,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Icon(Icons.business_outlined),
                        ),
                      ),
                title: Text(rpc.companyName ?? '—'),
                subtitle: const Text('Current company'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: Text(Uri.parse(session.serverUrl).host),
                subtitle: Text('Database: ${session.db}'),
              ),
            ]),
            _section('Settings', [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: [
                    const Icon(Icons.dark_mode_outlined),
                    const SizedBox(width: 16),
                    const Expanded(child: Text('Appearance')),
                    SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: const [
                        ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                        ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                        ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                      ],
                      selected: {themeMode.value},
                      onSelectionChanged: (s) => _setThemeMode(s.first),
                    ),
                  ],
                ),
              ),
              if (_biometricAvailable) ...[
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint),
                  title: const Text('Quick unlock'),
                  subtitle: const Text('Fingerprint, face or screen lock'),
                  value: _biometricOn,
                  onChanged: _toggleBiometric,
                ),
              ],
            ]),
            _section('Account', [
              ListTile(
                leading: const Icon(Icons.language),
                title: const Text('Open web version'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WebViewScreen(session: session, title: rpc.companyName ?? 'Odoo'),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.logout, color: scheme.error),
                title: Text(
                  'Sign out',
                  style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
                ),
                onTap: () => endSession(destroy: session),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
