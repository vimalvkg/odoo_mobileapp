import 'package:flutter/material.dart';

import '../app_navigation.dart';
import '../biometric.dart';
import '../l10n.dart';
import '../odoo/rpc.dart';
import '../session_store.dart';
import '../theme.dart';
import '../widgets/record_avatar.dart';
import 'home_screen.dart';
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
  List<({String code, String name})> _languages = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadLanguages();
  }

  Future<void> _loadLanguages() async {
    try {
      final languages = await widget.rpc.loadLanguages();
      if (mounted) setState(() => _languages = languages);
    } on OdooException {
      // Without the list, the current language just shows by its code.
    }
  }

  String get _languageName {
    final code = widget.rpc.userContext['lang']?.toString() ?? appLanguage.value;
    return _languages.where((l) => l.code == code).firstOrNull?.name ?? code;
  }

  /// Picks from the languages installed in this database and saves it as
  /// the user's Odoo preference, then reloads so menus and records come
  /// back in that language.
  Future<void> _pickLanguage() async {
    final current = widget.rpc.userContext['lang']?.toString();
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
              child: Text(tr('Language'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final l in _languages)
                    ListTile(
                      title: Text(l.name),
                      trailing: l.code == current ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
                      onTap: () => Navigator.of(sheetContext).pop(l.code),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || picked == current || !mounted) return;
    try {
      await widget.rpc.setUserLanguage(picked);
    } catch (e) {
      if (mounted) handleRpcError(context, e);
      return;
    }
    await setAppLanguage(picked);
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => HomeScreen(session: widget.rpc.session, rpc: widget.rpc)),
      (_) => false,
    );
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
    if (on && !await biometricUnlock(tr('Confirm to enable quick unlock'))) return;
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
            Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: Text(tr('Profile'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
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
            _section(tr('Company'), [
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
                subtitle: Text(tr('Current company')),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: Text(Uri.parse(session.serverUrl).host),
                subtitle: Text(tr('Database: {db}', {'db': session.db})),
              ),
            ]),
            _section(tr('Settings'), [
              ListTile(
                leading: const Icon(Icons.translate),
                title: Text(tr('Language')),
                subtitle: Text(_languageName),
                trailing: const Icon(Icons.chevron_right),
                onTap: _languages.length > 1 ? _pickLanguage : null,
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: [
                    const Icon(Icons.dark_mode_outlined),
                    const SizedBox(width: 16),
                    Expanded(child: Text(tr('Appearance'))),
                    SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: [
                        ButtonSegment(value: ThemeMode.system, label: Text(tr('Auto'))),
                        ButtonSegment(value: ThemeMode.light, label: Text(tr('Light'))),
                        ButtonSegment(value: ThemeMode.dark, label: Text(tr('Dark'))),
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
                  title: Text(tr('Quick unlock')),
                  subtitle: Text(tr('Fingerprint, face or screen lock')),
                  value: _biometricOn,
                  onChanged: _toggleBiometric,
                ),
              ],
            ]),
            _section(tr('Account'), [
              ListTile(
                leading: const Icon(Icons.language),
                title: Text(tr('Open web version')),
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
                  tr('Sign out'),
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
