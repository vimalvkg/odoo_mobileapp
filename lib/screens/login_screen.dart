import 'package:flutter/material.dart';

import '../odoo_client.dart';
import '../session_store.dart';
import 'webview_screen.dart';

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
      MaterialPageRoute(builder: (_) => WebViewScreen(session: session)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.content_cut, color: Theme.of(context).colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Sign in to Tailorline',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
                ),
                if (widget.notice != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.onSecondaryContainer),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.notice!,
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSecondaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                TextField(
                  controller: _serverCtrl,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Server', hintText: 'yourshop.odoo.com'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _dbCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Database', hintText: 'tailer19'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _loginCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Username', hintText: 'you@example.com'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.error_outline, size: 16, color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _errorText!,
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
