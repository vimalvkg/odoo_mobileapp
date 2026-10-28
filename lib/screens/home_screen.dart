import 'package:flutter/material.dart';

import '../app_navigation.dart';
import '../odoo/menus.dart';
import '../odoo/rpc.dart';
import '../session_store.dart';
import '../widgets/error_view.dart';
import '../widgets/odoo_image.dart';
import '../theme.dart';
import 'action_screen.dart';
import 'webview_screen.dart';

/// Grid of the apps installed in the connected database, built from its
/// menus, so it adapts to whatever modules the database has.
class HomeScreen extends StatefulWidget {
  final Session session;

  /// Injected in tests; built from [session] otherwise.
  final OdooRpc? rpc;

  const HomeScreen({super.key, required this.session, this.rpc});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final OdooRpc _rpc = widget.rpc ?? OdooRpc(widget.session);
  List<OdooMenu>? _apps;
  Object? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _rpc.loadSessionInfo();
      final apps = await _rpc.loadApps();
      if (mounted) setState(() => _apps = apps);
    } catch (e) {
      if (!mounted) return;
      if (e is OdooException && e.isSessionExpired) {
        endSession(notice: sessionEndedNotice);
        return;
      }
      setState(() => _error = e);
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _apps = null;
    });
    _load();
  }

  void _openMenu(OdooMenu app, OdooMenu menu) {
    final target = menu.firstAction;
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${menu.name} has nothing to open.')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ActionScreen(
        rpc: _rpc,
        actionId: target.actionId!,
        title: target == app ? app.name : target.name,
        app: app,
        menuId: target.id,
      ),
    ));
  }

  void _showProfile() {
    final session = widget.session;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: LetterAvatar(text: _rpc.userName ?? session.login, size: 44, circle: true),
              title: Text(_rpc.userName ?? session.login, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(session.login),
            ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(Uri.parse(session.serverUrl).host),
              subtitle: Text([session.db, if (_rpc.companyName != null) _rpc.companyName!].join(' · ')),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('Open web version'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => WebViewScreen(session: session, title: 'Odoo'),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                endSession(destroy: session);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _appGrid(List<OdooMenu> apps) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 96,
        mainAxisExtent: 112,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: apps.length,
      itemBuilder: (_, i) {
        final app = apps[i];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openMenu(app, app),
          child: Column(
            children: [
              const SizedBox(height: 4),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: AppIcon(app: app, serverUrl: widget.session.serverUrl, size: 60),
              ),
              const SizedBox(height: 8),
              Text(
                app.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, height: 1.2, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        );
      },
    );
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    final part = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');
    final first = (_rpc.userName ?? '').split(' ').first;
    return first.isEmpty ? part : '$part, $first';
  }

  /// Searching matches apps and every menu inside them, like Odoo's home
  /// menu search.
  Widget _searchResults(List<OdooMenu> apps) {
    final q = _query.toLowerCase();
    final results = [
      for (final app in apps)
        for (final (menu, path) in app.actionsWithPath())
          if (path.toLowerCase().contains(q)) (app, menu, path),
    ];
    if (results.isEmpty) return const Center(child: Text('No apps or menus match'));
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) {
        final (app, menu, path) = results[i];
        return ListTile(
          leading: AppIcon(app: app, serverUrl: widget.session.serverUrl, size: 32),
          title: Text(menu.name),
          subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => _openMenu(app, menu),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final apps = _apps;
    final Widget body;
    if (_error != null) {
      body = ErrorView.fromError(_error!, onRetry: _retry);
    } else if (apps == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (apps.isEmpty) {
      body = ErrorView(
        icon: Icons.apps_outlined,
        title: 'No apps',
        message: 'This user has no apps installed or no access to any.',
        onRetry: _retry,
      );
    } else {
      final scheme = Theme.of(context).colorScheme;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(_greeting, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          ),
          if (_rpc.companyName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
              child: Text(_rpc.companyName!, style: TextStyle(fontSize: 14, color: scheme.outline)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search apps and menus',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
              ),
              onChanged: (q) => setState(() => _query = q.trim()),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _query.isEmpty ? _appGrid(apps) : _searchResults(apps),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(appName),
        actions: [
          IconButton(
            tooltip: 'Account',
            onPressed: _showProfile,
            icon: LetterAvatar(text: _rpc.userName ?? widget.session.login, size: 34, circle: true),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
    );
  }
}
