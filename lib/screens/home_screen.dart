import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_navigation.dart';
import '../odoo/format.dart';
import '../odoo/menus.dart';
import '../odoo/rpc.dart';
import '../session_store.dart';
import '../theme.dart';
import '../widgets/error_view.dart';
import '../widgets/odoo_image.dart';
import '../widgets/record_avatar.dart';
import '../widgets/skeleton.dart';
import 'action_screen.dart';
import 'activities_screen.dart';
import 'profile_screen.dart';
import 'webview_screen.dart';

const _discussMenu = 'mail.menu_root_discuss';

/// The signed-in shell: Apps, Activities, Discuss and Profile tabs. Every tab
/// comes from the connected database — the apps grid from its menus, and
/// Activities/Discuss only when Discuss (`mail`) is installed.
class HomeScreen extends StatefulWidget {
  final Session session;

  /// Injected in tests; built from [session] otherwise.
  final OdooRpc? rpc;

  const HomeScreen({super.key, required this.session, this.rpc});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _Tab { apps, activities, discuss, profile }

class _HomeScreenState extends State<HomeScreen> {
  late final OdooRpc _rpc = widget.rpc ?? OdooRpc(widget.session);
  final _activitiesKey = GlobalKey<ActivitiesScreenState>();

  List<OdooMenu>? _apps;
  Object? _error;
  String _query = '';
  List<int> _recentIds = [];
  int _overdue = 0;
  int _dueToday = 0;
  _Tab _tab = _Tab.apps;

  /// Tabs are built on first visit (the Discuss web view is heavy).
  final Set<_Tab> _visited = {_Tab.apps};

  @override
  void initState() {
    super.initState();
    _load();
  }

  OdooMenu? get _discuss => _apps?.where((a) => a.xmlid == _discussMenu).firstOrNull;

  List<_Tab> get _tabs => [
    _Tab.apps,
    if (_discuss != null) ...[_Tab.activities, _Tab.discuss],
    _Tab.profile,
  ];

  Future<void> _load() async {
    try {
      await _rpc.loadSessionInfo();
      final apps = await _rpc.loadApps();
      final recent = await AppPrefs.recentMenus(widget.session.serverUrl, widget.session.db);
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _recentIds = recent;
        _error = null;
      });
      _loadBranding();
      if (_discuss != null) _loadActivityCounts();
    } catch (e) {
      if (!mounted) return;
      if (e is OdooException && e.isSessionExpired) {
        endSession(notice: sessionEndedNotice);
        return;
      }
      setState(() => _error = e);
    }
  }

  /// Re-themes the app with the company's own colour, remembered per database
  /// so the next launch starts in the right colours.
  Future<void> _loadBranding() async {
    final color = parseHexColor(await _rpc.loadCompanyColor());
    brandColor.value = color ?? defaultBrandColor;
    await AppPrefs.setBrandColor(widget.session.serverUrl, widget.session.db, color?.toARGB32());
  }

  Future<void> _loadActivityCounts() async {
    final today = serializeOdooDate(DateTime.now());
    Future<int> count(String op) async {
      final n = await _rpc.callKw(
        'mail.activity',
        'search_count',
        args: [
          [
            ['user_id', '=', _rpc.uid],
            ['date_deadline', op, today],
          ],
        ],
      );
      return n is int ? n : 0;
    }

    try {
      final (overdue, dueToday) = await (count('<'), count('=')).wait;
      if (mounted) {
        setState(() {
          _overdue = overdue;
          _dueToday = dueToday;
        });
      }
    } catch (_) {
      // Counts are a convenience; the Activities tab reports real errors.
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _apps = null;
    });
    _load();
  }

  Future<void> _openMenu(OdooMenu app, OdooMenu menu) async {
    final target = menu.firstAction;
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${menu.name} has nothing to open.')));
      return;
    }
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActionScreen(
          rpc: _rpc,
          actionId: target.actionId!,
          title: target == app ? app.name : target.name,
          app: app,
          menuId: target.id,
        ),
      ),
    );
    final recent = await AppPrefs.recentMenus(widget.session.serverUrl, widget.session.db);
    if (mounted) setState(() => _recentIds = recent);
    if (_discuss != null) _loadActivityCounts();
  }

  void _selectTab(_Tab tab) {
    HapticFeedback.selectionClick();
    setState(() {
      _tab = tab;
      _visited.add(tab);
    });
    if (tab == _Tab.activities) _activitiesKey.currentState?.reload();
  }

  // ---- Apps tab ----

  String get _greeting {
    final hour = DateTime.now().hour;
    final part = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');
    final first = (_rpc.userName ?? '').split(' ').first;
    return first.isEmpty ? part : '$part, $first';
  }

  /// Recently opened menus that still exist in this database.
  List<(OdooMenu, OdooMenu)> _recent(List<OdooMenu> apps) => [
    for (final id in _recentIds)
      for (final app in apps)
        if (app.find(id) case final menu?) (app, menu),
  ];

  Widget _activityCard() {
    if (_overdue + _dueToday == 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final parts = [if (_overdue > 0) '$_overdue overdue', if (_dueToday > 0) '$_dueToday due today'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Card(
        color: scheme.primaryContainer,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _selectTab(_Tab.activities),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primary,
                  child: Icon(Icons.event_note, color: scheme.onPrimary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your activities',
                        style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
                      ),
                      Text(parts.join(' · '), style: TextStyle(color: scheme.onPrimaryContainer)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _recentRow(List<(OdooMenu, OdooMenu)> recent) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final (app, menu) in recent)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: AppIcon(app: app, serverUrl: widget.session.serverUrl, size: 22),
                label: Text(menu == app ? app.name : menu.name),
                onPressed: () => _openMenu(app, menu),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: Theme.of(context).colorScheme.outline,
      ),
    ),
  );

  Widget _appTile(OdooMenu app) {
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
  }

  List<Widget> _searchSlivers(List<OdooMenu> apps) {
    final q = _query.toLowerCase();
    final results = [
      for (final app in apps)
        for (final (menu, path) in app.actionsWithPath())
          if (path.toLowerCase().contains(q)) (app, menu, path),
    ];
    if (results.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('No apps or menus match')),
          ),
        ),
      ];
    }
    return [
      SliverList.builder(
        itemCount: results.length,
        itemBuilder: (_, i) {
          final (app, menu, path) = results[i];
          return ListTile(
            leading: AppIcon(app: app, serverUrl: widget.session.serverUrl, size: 36),
            title: Text(menu.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _openMenu(app, menu),
          );
        },
      ),
    ];
  }

  Widget _appsTab() {
    final apps = _apps;
    final scheme = Theme.of(context).colorScheme;
    final Widget body;
    if (_error != null) {
      body = ErrorView.fromError(_error!, onRetry: _retry);
    } else if (apps == null) {
      body = const SkeletonGrid();
    } else if (apps.isEmpty) {
      body = ErrorView(
        icon: Icons.apps_outlined,
        title: 'No apps',
        message: 'This user has no apps installed or no access to any.',
        onRetry: _retry,
      );
    } else {
      final recent = _recent(apps);
      body = RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Text(_greeting, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                    child: Text('What would you like to work on?', style: TextStyle(color: scheme.outline)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Search apps and menus',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (q) => setState(() => _query = q.trim()),
                    ),
                  ),
                  if (_query.isEmpty) ...[
                    _activityCard(),
                    if (recent.isNotEmpty) ...[_sectionTitle('Recent'), _recentRow(recent)],
                    _sectionTitle('All apps'),
                  ],
                ],
              ),
            ),
            if (_query.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 96,
                    mainAxisExtent: 112,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: apps.length,
                  itemBuilder: (_, i) => _appTile(apps[i]),
                ),
              )
            else
              ..._searchSlivers(apps),
          ],
        ),
      );
    }

    final logo = _rpc.companyLogoUrl;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            if (logo != null) ...[
              SizedBox(
                height: 28,
                width: 28,
                child: Image.network(logo, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox()),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(child: Text(_rpc.companyName ?? '', overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: () => _selectTab(_Tab.profile),
            icon: RecordAvatar(
              rpc: _rpc,
              model: 'res.users',
              id: _rpc.uid,
              imageField: 'avatar_128',
              text: _rpc.userName ?? widget.session.login,
              size: 34,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
    );
  }

  Widget _buildTab(_Tab tab) {
    switch (tab) {
      case _Tab.apps:
        return _appsTab();
      case _Tab.activities:
        return ActivitiesScreen(
          key: _activitiesKey,
          rpc: _rpc,
          onDueCount: (overdue, today) {
            if (mounted) {
              setState(() {
                _overdue = overdue;
                _dueToday = today;
              });
            }
          },
        );
      case _Tab.discuss:
        return WebViewScreen(
          session: widget.session,
          path: '/odoo/action-${_discuss!.firstAction?.actionId}',
          title: _discuss!.name,
          active: _tab == _Tab.discuss,
          onBackAtStart: () => _selectTab(_Tab.apps),
        );
      case _Tab.profile:
        return ProfileScreen(rpc: _rpc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    final index = tabs.indexOf(_tab).clamp(0, tabs.length - 1);
    final due = _overdue + _dueToday;

    // Back from another tab returns to Apps (Discuss handles its own history).
    return PopScope(
      canPop: _tab == _Tab.apps || _tab == _Tab.discuss,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _tab != _Tab.apps) _selectTab(_Tab.apps);
      },
      child: Scaffold(
        body: IndexedStack(
          index: index,
          children: [for (final t in tabs) _visited.contains(t) ? _buildTab(t) : const SizedBox.shrink()],
        ),
        bottomNavigationBar: _apps == null || tabs.length < 2
            ? null
            : NavigationBar(
                selectedIndex: index,
                onDestinationSelected: (i) => _selectTab(tabs[i]),
                destinations: [
                  for (final t in tabs)
                    switch (t) {
                      _Tab.apps => const NavigationDestination(
                        icon: Icon(Icons.apps_outlined),
                        selectedIcon: Icon(Icons.apps),
                        label: 'Apps',
                      ),
                      _Tab.activities => NavigationDestination(
                        icon: Badge(
                          isLabelVisible: due > 0,
                          label: Text('$due'),
                          child: const Icon(Icons.event_note_outlined),
                        ),
                        selectedIcon: const Icon(Icons.event_note),
                        label: 'Activities',
                      ),
                      _Tab.discuss => const NavigationDestination(
                        icon: Icon(Icons.forum_outlined),
                        selectedIcon: Icon(Icons.forum),
                        label: 'Discuss',
                      ),
                      _Tab.profile => const NavigationDestination(
                        icon: Icon(Icons.person_outline),
                        selectedIcon: Icon(Icons.person),
                        label: 'Profile',
                      ),
                    },
                ],
              ),
      ),
    );
  }
}
