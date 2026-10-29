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

/// The signed-in shell: Home, Activities, quick create, Discuss and Profile.
/// Everything comes from the connected database — the apps from its menus,
/// Activities/Discuss only when Discuss (`mail`) is installed.
class HomeScreen extends StatefulWidget {
  final Session session;

  /// Injected in tests; built from [session] otherwise.
  final OdooRpc? rpc;

  const HomeScreen({super.key, required this.session, this.rpc});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _Tab { home, activities, discuss, profile }

class _HomeScreenState extends State<HomeScreen> {
  late final OdooRpc _rpc = widget.rpc ?? OdooRpc(widget.session);
  final _activitiesKey = GlobalKey<ActivitiesScreenState>();

  List<OdooMenu>? _apps;
  Object? _error;
  String _query = '';
  List<int> _recentIds = [];
  List<int> _pinnedIds = [];
  int _overdue = 0;
  int _dueToday = 0;

  /// Inbox notifications; null when the database can't report them.
  int? _unread;
  _Tab _tab = _Tab.home;

  /// Tabs are built on first visit (the Discuss web view is heavy).
  final Set<_Tab> _visited = {_Tab.home};

  String get _server => widget.session.serverUrl;
  String get _db => widget.session.db;

  @override
  void initState() {
    super.initState();
    _load();
  }

  OdooMenu? get _discuss => _apps?.where((a) => a.xmlid == _discussMenu).firstOrNull;

  Future<void> _load() async {
    try {
      await _rpc.loadSessionInfo();
      final apps = await _rpc.loadApps();
      final (recent, pinned) = await (AppPrefs.recentMenus(_server, _db), PinnedMenus.load(_server, _db)).both;
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _recentIds = recent;
        _pinnedIds = pinned;
        _error = null;
      });
      _loadBranding();
      if (_discuss != null) _loadCounts();
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
    await AppPrefs.setBrandColor(_server, _db, color?.toARGB32());
  }

  Future<void> _loadCounts() async {
    final today = serializeOdooDate(DateTime.now());
    Future<int> count(String model, List<dynamic> domain) async {
      final n = await _rpc.callKw(model, 'search_count', args: [domain]);
      return n is int ? n : 0;
    }

    try {
      final (overdue, dueToday) = await (
        count('mail.activity', [
          ['user_id', '=', _rpc.uid],
          ['date_deadline', '<', today],
        ]),
        count('mail.activity', [
          ['user_id', '=', _rpc.uid],
          ['date_deadline', '=', today],
        ]),
      ).both;
      if (mounted) {
        setState(() {
          _overdue = overdue;
          _dueToday = dueToday;
        });
      }
    } catch (_) {
      // Counts are a convenience; the Activities tab reports real errors.
    }
    try {
      // Messages waiting in the user's Discuss inbox.
      final unread = await count('mail.message', [
        ['needaction', '=', true],
      ]);
      if (mounted) setState(() => _unread = unread);
    } catch (_) {
      if (mounted) setState(() => _unread = null);
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
    final recent = await AppPrefs.recentMenus(_server, _db);
    if (mounted) setState(() => _recentIds = recent);
    if (_discuss != null) _loadCounts();
  }

  Future<void> _togglePin(OdooMenu menu) async {
    HapticFeedback.mediumImpact();
    final target = menu.firstAction ?? menu;
    final pinned = await PinnedMenus.toggle(_server, _db, target.id);
    final pins = await PinnedMenus.load(_server, _db);
    if (!mounted) return;
    setState(() => _pinnedIds = pins);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(pinned ? 'Pinned ${target.name} to Home' : 'Unpinned ${target.name}')));
  }

  void _selectTab(_Tab tab) {
    HapticFeedback.selectionClick();
    setState(() {
      _tab = tab;
      _visited.add(tab);
    });
    if (tab == _Tab.activities) _activitiesKey.currentState?.reload();
  }

  /// Menus that still exist in this database, as (app, menu) pairs.
  List<(OdooMenu, OdooMenu)> _resolve(List<int> ids) {
    final apps = _apps ?? const <OdooMenu>[];
    return [
      for (final id in ids)
        for (final app in apps)
          if (app.find(id) case final menu?) (app, menu),
    ];
  }

  /// The centre "+": new records for the menus the user works in.
  void _showQuickCreate() {
    HapticFeedback.selectionClick();
    final seen = <int>{};
    final targets = [
      for (final (app, menu) in [..._resolve(_pinnedIds), ..._resolve(_recentIds)])
        if (menu.actionId != null && seen.add(menu.id)) (app, menu),
    ].take(8).toList();
    final c = AppColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Create new', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            if (targets.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Text(
                  'Open or pin a menu first (long-press an app) and it will appear here for quick creation.',
                  style: TextStyle(color: c.muted),
                ),
              ),
            for (final (app, menu) in targets)
              ListTile(
                leading: AppIcon(app: app, serverUrl: _server, size: 40),
                title: Text('New in ${menu.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(app.name),
                trailing: const Icon(Icons.add),
                onTap: () async {
                  Navigator.of(sheet).pop();
                  try {
                    final ok = await openCreateForm(context, _rpc, menu.actionId!, menu.name);
                    if (!ok && mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('${menu.name} can\'t create records here.')));
                    }
                  } catch (e) {
                    if (mounted) handleRpcError(context, e);
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---- Home tab ----

  String get _greeting {
    final hour = DateTime.now().hour;
    final part = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');
    final first = (_rpc.userName ?? '').split(' ').first;
    return first.isEmpty ? part : '$part, $first';
  }

  int get _attention => _overdue + _dueToday + (_unread ?? 0);

  Widget _topBar() {
    final c = AppColors.of(context);
    final logo = _rpc.companyLogoUrl;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: logo == null
              ? Icon(Icons.business, color: brandOf(context), size: 20)
              : Image.network(
                  logo,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Icon(Icons.business, color: brandOf(context), size: 20),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _rpc.companyName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              Text(_db, style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ),
        ),
        if (_discuss != null)
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => _selectTab(_Tab.discuss),
            style: IconButton.styleFrom(
              backgroundColor: c.card,
              side: BorderSide(color: c.border),
              fixedSize: const Size(44, 44),
            ),
            icon: Badge(isLabelVisible: (_unread ?? 0) > 0, smallSize: 9, child: const Icon(Icons.notifications_none)),
          ),
        const SizedBox(width: 6),
        InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _selectTab(_Tab.profile),
          child: Semantics(
            label: 'Profile',
            button: true,
            child: RecordAvatar(
              rpc: _rpc,
              model: 'res.users',
              id: _rpc.uid,
              imageField: 'avatar_128',
              text: _rpc.userName ?? widget.session.login,
              size: 44,
            ),
          ),
        ),
      ],
    );
  }

  Widget _counter(String value, String label, Color color, VoidCallback onTap) {
    final c = AppColors.of(context);
    return Expanded(
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color),
                ),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(fontSize: 12, color: c.muted), maxLines: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        ?trailing,
      ],
    ),
  );

  Widget _menuChips(List<(OdooMenu, OdooMenu)> menus) {
    final c = AppColors.of(context);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          for (final (app, menu) in menus)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: c.card,
                shape: StadiumBorder(side: BorderSide(color: c.border)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => _openMenu(app, menu),
                  onLongPress: () => _togglePin(menu),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
                    child: Row(
                      children: [
                        AppIcon(app: app, serverUrl: _server, size: 30),
                        const SizedBox(width: 8),
                        Text(
                          menu == app ? app.name : menu.name,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _appTile(OdooMenu app) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _openMenu(app, app),
      onLongPress: () => _togglePin(app),
      child: Column(
        children: [
          const SizedBox(height: 4),
          AppIcon(app: app, serverUrl: _server, size: 60),
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
            leading: AppIcon(app: app, serverUrl: _server, size: 40),
            title: Text(menu.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: _pinnedIds.contains(menu.id) ? 'Unpin' : 'Pin to Home',
              icon: Icon(_pinnedIds.contains(menu.id) ? Icons.push_pin : Icons.push_pin_outlined),
              onPressed: () => _togglePin(menu),
            ),
            onTap: () => _openMenu(app, menu),
          );
        },
      ),
    ];
  }

  Widget _homeTab() {
    final apps = _apps;
    final c = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (_error != null) {
      return Scaffold(body: SafeArea(child: ErrorView.fromError(_error!, onRetry: _retry)));
    }
    if (apps == null) {
      return const Scaffold(body: SafeArea(child: SkeletonGrid()));
    }
    if (apps.isEmpty) {
      return Scaffold(
        body: ErrorView(
          icon: Icons.apps_outlined,
          title: 'No apps',
          message: 'This user has no apps installed or no access to any.',
          onRetry: _retry,
        ),
      );
    }

    final pinned = _resolve(_pinnedIds);
    final recent = [
      for (final r in _resolve(_recentIds))
        if (!_pinnedIds.contains(r.$2.id)) r,
    ].take(6).toList();
    final hasMail = _discuss != null;
    final attention = _attention;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _topBar(),
                      const SizedBox(height: 20),
                      Text(
                        _greeting,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        !hasMail
                            ? 'What would you like to work on?'
                            : attention == 0
                            ? "You're all caught up"
                            : attention == 1
                            ? '1 thing needs your attention'
                            : '$attention things need your attention',
                        style: TextStyle(fontSize: 14, color: c.muted),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'Search apps and menus',
                          fillColor: c.card,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide(color: c.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide(color: c.border),
                          ),
                        ),
                        onChanged: (q) => setState(() => _query = q.trim()),
                      ),
                      if (hasMail && _query.isEmpty) ...[
                        const SizedBox(height: 14),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _counter(
                                '$_overdue',
                                'Overdue activities',
                                const Color(0xFFB3261E),
                                () => _selectTab(_Tab.activities),
                              ),
                              const SizedBox(width: 10),
                              _counter(
                                '$_dueToday',
                                'Due today',
                                const Color(0xFF9A5B00),
                                () => _selectTab(_Tab.activities),
                              ),
                              if (_unread != null) ...[
                                const SizedBox(width: 10),
                                _counter('$_unread', 'Unread messages', scheme.primary, () => _selectTab(_Tab.discuss)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_query.isEmpty) ...[
                if (pinned.isNotEmpty) ...[
                  SliverToBoxAdapter(child: _sectionTitle('Pinned')),
                  SliverToBoxAdapter(child: _menuChips(pinned)),
                ],
                if (recent.isNotEmpty) ...[
                  SliverToBoxAdapter(child: _sectionTitle('Recent')),
                  SliverToBoxAdapter(child: _menuChips(recent)),
                ],
                SliverToBoxAdapter(
                  child: _sectionTitle(
                    'Apps',
                    trailing: Text('Long-press to pin', style: TextStyle(fontSize: 12, color: c.muted)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
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
                ),
              ] else ...[
                ..._searchSlivers(apps),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab(_Tab tab) {
    switch (tab) {
      case _Tab.home:
        return _homeTab();
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
          onBackAtStart: () => _selectTab(_Tab.home),
        );
      case _Tab.profile:
        return ProfileScreen(rpc: _rpc);
    }
  }

  Widget _navItem(_Tab tab, IconData icon, IconData selectedIcon, String label, {int badge = 0}) {
    final selected = _tab == tab;
    final scheme = Theme.of(context).colorScheme;
    final c = AppColors.of(context);
    final color = selected ? scheme.primary : c.muted;
    return Expanded(
      child: InkWell(
        onTap: () => _selectTab(tab),
        child: Semantics(
          selected: selected,
          button: true,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text('$badge'),
                child: Icon(selected ? selectedIcon : icon, color: color),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: color, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final c = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final hasMail = _discuss != null;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              _navItem(_Tab.home, Icons.home_outlined, Icons.home, 'Home'),
              if (hasMail)
                _navItem(_Tab.activities, Icons.task_alt, Icons.task_alt, 'Activities', badge: _overdue + _dueToday),
              Expanded(
                child: Center(
                  child: Transform.translate(
                    offset: const Offset(0, -14),
                    child: Material(
                      color: scheme.primary,
                      elevation: 4,
                      shadowColor: scheme.primary.withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: _showQuickCreate,
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: Icon(Icons.add, color: scheme.onPrimary, size: 28, semanticLabel: 'Quick create'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (hasMail) _navItem(_Tab.discuss, Icons.chat_bubble_outline, Icons.chat_bubble, 'Discuss'),
              _navItem(_Tab.profile, Icons.person_outline, Icons.person, 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _Tab.home,
      if (_discuss != null) ...[_Tab.activities, _Tab.discuss],
      _Tab.profile,
    ];
    final index = tabs.indexOf(_tab).clamp(0, tabs.length - 1);

    // Back from another tab returns Home (Discuss handles its own history).
    return PopScope(
      canPop: _tab == _Tab.home || _tab == _Tab.discuss,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _tab != _Tab.home) _selectTab(_Tab.home);
      },
      child: Scaffold(
        body: IndexedStack(
          index: index,
          children: [for (final t in tabs) _visited.contains(t) ? _buildTab(t) : const SizedBox.shrink()],
        ),
        bottomNavigationBar: _apps == null ? null : _bottomBar(),
      ),
    );
  }
}
