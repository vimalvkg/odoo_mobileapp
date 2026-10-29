import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n.dart';
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

  /// The database's company logo, once server and database are filled in.
  String? _logoUrl;
  Timer? _brandingDebounce;

  @override
  void initState() {
    super.initState();
    _prefill();
    _serverCtrl.addListener(_scheduleBranding);
    _dbCtrl.addListener(_scheduleBranding);
  }

  void _scheduleBranding() {
    _brandingDebounce?.cancel();
    _brandingDebounce = Timer(const Duration(milliseconds: 700), _updateBranding);
  }

  /// Shows the company logo (public in Odoo) and the colours remembered for
  /// this database, before the user has even signed in.
  Future<void> _updateBranding() async {
    final server = _serverCtrl.text.trim();
    final db = _dbCtrl.text.trim();
    if (server.isEmpty || db.isEmpty) {
      if (mounted) setState(() => _logoUrl = null);
      brandColor.value = defaultBrandColor;
      return;
    }
    final url = normalizeServerUrl(server);
    final cached = await AppPrefs.brandColor(url, db);
    if (!mounted) return;
    brandColor.value = cached == null ? defaultBrandColor : Color(cached);
    setState(() => _logoUrl = OdooClient.publicLogoUrl(url, db));
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
    _brandingDebounce?.cancel();
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
      setState(() => _errorText = tr('Enter the server first.'));
      return;
    }
    setState(() => _errorText = null);
    final databases = await OdooClient.listDatabases(normalizeServerUrl(server));
    if (!mounted) return;
    if (databases == null || databases.isEmpty) {
      setState(() => _errorText = tr("This server doesn't list its databases. Type the name."));
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
            for (final db in databases) ListTile(title: Text(db), onTap: () => Navigator.of(sheetContext).pop(db)),
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
      setState(() => _errorText = tr('Fill in all fields.'));
      return;
    }

    setState(() {
      _loading = true;
      _errorText = null;
    });

    final serverUrl = normalizeServerUrl(server);
    final result = await OdooClient.authenticate(serverUrl: serverUrl, db: db, login: login, password: password);

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
    await setAppLanguage(result.lang);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(session: session)));
  }

  /// The app's own text before sign-in; once signed in, the user's Odoo
  /// language takes over.
  Future<void> _toggleLanguage() async {
    await setAppLanguage(isArabic ? 'en_US' : 'ar_001');
    if (mounted) setState(() {});
  }

  Widget _banner(IconData icon, String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: fg)),
          ),
        ],
      ),
    );
  }

  /// A label above a filled input, as in the design.
  Widget _field(
    String label,
    TextEditingController controller,
    IconData icon, {
    String? hint,
    Widget? suffix,
    bool obscure = false,
    TextInputType? keyboard,
    TextInputAction action = TextInputAction.next,
    Iterable<String>? autofill,
    bool ltr = false,
    ValueChanged<String>? onSubmitted,
  }) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.muted),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboard,
          textDirection: ltr ? TextDirection.ltr : null,
          textInputAction: action,
          autocorrect: false,
          autofillHints: autofill,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: c.muted),
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.card,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: _loading ? null : _toggleLanguage,
                    icon: const Icon(Icons.translate, size: 18),
                    // Each language is named in itself, so it's findable from the other.
                    label: Text(isArabic ? 'English' : 'العربية'),
                  ),
                ),
                const SizedBox(height: 8),
                Center(child: BrandMark(size: 64, onBrand: false, logoUrl: _logoUrl)),
                const SizedBox(height: 18),
                Text(
                  tr('Welcome back'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: c.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  tr('Sign in to your Odoo database'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: c.muted),
                ),
                const SizedBox(height: 28),
                if (widget.notice != null) ...[
                  _banner(Icons.info_outline, tr(widget.notice!), scheme.secondaryContainer, scheme.onSecondaryContainer),
                  const SizedBox(height: 16),
                ],
                _field(
                  tr('Server'),
                  _serverCtrl,
                  Icons.dns_outlined,
                  hint: 'erp.yourcompany.com',
                  keyboard: TextInputType.url,
                  ltr: true,
                ),
                const SizedBox(height: 14),
                _field(
                  tr('Database'),
                  _dbCtrl,
                  Icons.storage_outlined,
                  ltr: true,
                  suffix: IconButton(
                    icon: const Icon(Icons.expand_more),
                    tooltip: tr('Choose from server'),
                    onPressed: _loading ? null : _pickDatabase,
                  ),
                ),
                const SizedBox(height: 14),
                _field(
                  tr('Email or username'),
                  _loginCtrl,
                  Icons.person_outline,
                  hint: 'you@company.com',
                  keyboard: TextInputType.emailAddress,
                  ltr: true,
                  autofill: const [AutofillHints.username],
                ),
                const SizedBox(height: 14),
                _field(
                  tr('Password'),
                  _passwordCtrl,
                  Icons.lock_outline,
                  obscure: _obscurePassword,
                  action: TextInputAction.done,
                  ltr: true,
                  autofill: const [AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                  suffix: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    tooltip: _obscurePassword ? tr('Show password') : tr('Hide password'),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                const SizedBox(height: 20),
                if (_errorText != null) ...[
                  _banner(Icons.error_outline, _errorText!, scheme.errorContainer, scheme.onErrorContainer),
                  const SizedBox(height: 16),
                ],
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  child: _loading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary),
                        )
                      : Text(tr('Sign in')),
                ),
                const SizedBox(height: 28),
                Text(
                  tr('Works with any Odoo 19 Community database'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
