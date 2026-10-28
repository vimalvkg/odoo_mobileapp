import 'package:flutter/material.dart';

import '../app_navigation.dart';
import '../odoo/menus.dart';
import '../odoo/rpc.dart';
import '../session_store.dart';
import '../widgets/error_view.dart';
import '../widgets/odoo_image.dart';
import 'action_screen.dart';
import 'webview_screen.dart';

/// Grid of the apps installed in the connected database, built from its
/// menus, so it adapts to whatever modules the database has.
class HomeScreen extends StatefulWidget {
  final Session session;

  const HomeScreen({super.key, required this.session});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final OdooRpc _rpc = OdooRpc(widget.session);
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
              leading: LetterAvatar(text: _rpc.userName ?? session.login, size: 40),
              title: Text(_rpc.userName ?? session.login),
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
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 104,
        mainAxisExtent: 112,
        crossAxisSpacing: 4,
      ),
      itemCount: apps.length,
      itemBuilder: (_, i) {
        final app = apps[i];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openMenu(app, app),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                AppIcon(app: app, serverUrl: widget.session.serverUrl),
                const SizedBox(height: 6),
                Text(
                  app.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
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
      body = Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search apps and menus', isDense: true),
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
        title: Text(_rpc.companyName ?? 'Apps'),
        actions: [
          IconButton(
            tooltip: 'Account',
            onPressed: _showProfile,
            icon: LetterAvatar(text: _rpc.userName ?? widget.session.login, size: 32),
          ),
        ],
      ),
      body: body,
    );
  }
}
