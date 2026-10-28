import 'package:flutter/material.dart';

import '../odoo_client.dart';
import '../session_store.dart';
import '../theme.dart';
import '../widgets/brand_mark.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  /// Shown above the form, e.g. to explain why the user was signed out.
  final String? notice;

  const LoginScreen({super.key, this.notice});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _serverCtrl = TextEditingController();
  final _dbCtrl = TextEditingController();
  final _loginCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final last = await SessionStore.lastLogin();
    if (last == null || !mounted) return;
    // Don't overwrite anything the user started typing while prefs loaded.
    if (_serverCtrl.text.isEmpty) _serverCtrl.text = last.serverUrl;
    if (_dbCtrl.text.isEmpty) _dbCtrl.text = last.db;
    if (_loginCtrl.text.isEmpty) _loginCtrl.text = last.login;
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _dbCtrl.dispose();
    _loginCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// Fills the database field from the server's list, when the server
  /// allows listing (`list_db`); otherwise the user types it.
  Future<void> _pickDatabase() async {
    final server = _serverCtrl.text.trim();
    if (server.isEmpty) {
      setState(() => _errorText = 'Enter the server first.');
      return;
    }
    setState(() => _errorText = null);
    final databases = await OdooClient.listDatabases(normalizeServerUrl(server));
    if (!mounted) return;
    if (databases == null || databases.isEmpty) {
      setState(() => _errorText = "This server doesn't list its databases. Type the name.");
      return;
    }
    if (databases.length == 1) {
      _dbCtrl.text = databases.first;
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final db in databases)
              ListTile(title: Text(db), onTap: () => Navigator.of(sheetContext).pop(db)),
          ],
        ),
      ),
    );
    if (picked != null) _dbCtrl.text = picked;
  }

  Future<void> _submit() async {
    final server = _serverCtrl.text.trim();
    final db = _dbCtrl.text.trim();
    final login = _loginCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (server.isEmpty || db.isEmpty || login.isEmpty || password.isEmpty) {
      setState(() => _errorText = 'Fill in all fields.');
      return;
    }

    setState(() {
      _loading = true;
      _errorText = null;
    });

    final serverUrl = normalizeServerUrl(server);
    final result = await OdooClient.authenticate(
      serverUrl: serverUrl,
      db: db,
      login: login,
      password: password,
    );

    if (!mounted) return;

    if (result.outcome != AuthOutcome.success) {
      setState(() {
        _loading = false;
        _errorText = result.errorMessage;
      });
      return;
    }

    final session = Session(serverUrl: serverUrl, db: db, login: login, sessionId: result.sessionId!);
    await SessionStore.save(session);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(session: session)),
    );
  }

  Widget _banner(IconData icon, String text, Color bg, Color fg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: fg))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(28, top + 48, 28, 72),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [brandColor, Color.lerp(brandColor, Colors.black, 0.35)!],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BrandMark(size: 56),
                  const SizedBox(height: 20),
                  const Text(
                    'Welcome',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sign in to your Odoo database',
                    style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.notice != null)
                            _banner(Icons.info_outline, widget.notice!, scheme.secondaryContainer,
                                scheme.onSecondaryContainer),
                          TextField(
                            controller: _serverCtrl,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Server',
                              hintText: 'mycompany.odoo.com',
                              prefixIcon: Icon(Icons.dns_outlined),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _dbCtrl,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: 'Database',
                              prefixIcon: const Icon(Icons.storage_outlined),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.list_alt_outlined),
                                tooltip: 'Choose from server',
                                onPressed: _loading ? null : _pickDatabase,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _loginCtrl,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.username],
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _passwordCtrl,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            onSubmitted: (_) => _submit(),
                          ),
                          if (_errorText != null) ...[
                            const SizedBox(height: 14),
                            _banner(Icons.error_outline, _errorText!, scheme.errorContainer, scheme.onErrorContainer),
                          ] else
                            const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _loading ? null : _submit,
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                            child: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Sign in'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Text(
              'Works with any Odoo 19 Community database',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
