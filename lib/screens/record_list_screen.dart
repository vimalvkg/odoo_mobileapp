import 'dart:async';

import 'package:flutter/material.dart';

import '../app_navigation.dart';
import '../odoo/domain.dart';
import '../odoo/expr.dart';
import '../odoo/format.dart';
import '../odoo/rpc.dart';
import '../odoo/view_arch.dart';
import '../theme.dart';
import '../widgets/error_view.dart';
import '../widgets/odoo_image.dart';
import 'record_form_screen.dart';
import 'webview_screen.dart';

const _pageSize = 40;
const _cardFieldTypes = {'char', 'integer', 'float', 'monetary', 'date', 'datetime', 'selection', 'many2one'};

/// Records of any model as mobile cards, built from the action's list (or
/// kanban) view, with search, the search view's filters and paging.
class RecordListScreen extends StatefulWidget {
  final OdooRpc rpc;
  final String model;
  final String title;
  final List<dynamic> domain;

  /// The action's domain used Python the app can't evaluate and was dropped.
  final bool domainIncomplete;
  final Map<String, dynamic> recordContext;

  /// View ids by type (`list`, `kanban`, `form`, `search`); null = default.
  final Map<String, int?> viewIds;

  /// Same screen in the web client, for "Open in web".
  final String? webPath;
  final Widget? drawer;

  const RecordListScreen({
    super.key,
    required this.rpc,
    required this.model,
    required this.title,
    this.domain = const [],
    this.domainIncomplete = false,
    this.recordContext = const {},
    this.viewIds = const {'list': null, 'form': null},
    this.webPath,
    this.drawer,
  });

  @override
  State<RecordListScreen> createState() => _RecordListScreenState();
}

class _RecordListScreenState extends State<RecordListScreen> {
  final _scroll = ScrollController();
  Timer? _debounce;

  ModelViews? _views;
  List<ArchField> _cardFields = [];
  List<(SearchFilter, List<dynamic>)> _filters = [];
  final Set<String> _activeFilters = {};
  bool _canCreate = true;

  List<Map<String, dynamic>> _records = [];
  bool _hasMore = true;
  bool _loadingMore = false;
  Object? _error;
  String _query = '';
  int? _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final cardType = widget.viewIds.containsKey('list') ? 'list' : 'kanban';
      final views = await widget.rpc.getViews(
        widget.model,
        [
          [widget.viewIds[cardType] ?? false, cardType],
          [widget.viewIds['search'] ?? false, 'search'],
        ],
        context: widget.recordContext,
      );
      final cardArch = views.archs[cardType];
      if (cardArch == null) throw const OdooException('This model has no list view.');

      final env = {...widget.rpc.evalEnv, 'context': {...widget.rpc.userContext, ...widget.recordContext}};
      final filters = <(SearchFilter, List<dynamic>)>[];
      for (final f in parseSearchFilters(views.archs['search'] ?? '<search/>')) {
        final domain = parseDomain(f.domain, env);
        if (domain != null) filters.add((f, domain));
      }

      _views = views;
      _canCreate = archAllows(cardArch, 'create');
      _cardFields = [
        for (final f in parseCardFields(cardArch))
          if (_cardFieldTypes.contains(views.fields[f.name]?['type'])) f,
      ];
      _filters = filters;
      _activeFilters
        ..clear()
        ..addAll([
          for (final (f, _) in filters)
            if (pyTruthy(widget.recordContext['search_default_${f.name}'])) f.name,
        ]);
      await _fetch(reset: true);
    } catch (e) {
      _onError(e);
    }
  }

  void _onError(Object e) {
    if (!mounted) return;
    if (e is OdooException && e.isSessionExpired) {
      endSession(notice: sessionEndedNotice);
      return;
    }
    if (_records.isEmpty) {
      setState(() => _error = e);
    } else {
      handleRpcError(context, e);
    }
  }

  List<dynamic> get _domain {
    final groups = <int, List<List<dynamic>>>{};
    for (final (f, domain) in _filters) {
      if (_activeFilters.contains(f.name)) groups.putIfAbsent(f.group, () => []).add(domain);
    }
    return andDomains([
      widget.domain,
      for (final g in groups.values) orDomains(g),
      if (_query.isNotEmpty)
        [
          ['display_name', 'ilike', _query],
        ],
    ]);
  }

  /// [reset] reloads from the top, keeping as many rows as are shown so a
  /// refresh after editing doesn't jump the list back.
  Future<void> _fetch({bool reset = false}) async {
    final views = _views;
    if (views == null) return;
    final fields = {'display_name', for (final f in _cardFields) f.name}.toList();
    final limit = reset ? (_records.length > _pageSize ? _records.length : _pageSize) : _pageSize;
    final domain = _domain;
    final (records, total) = await (
      widget.rpc.searchRead(
        widget.model,
        domain: domain,
        fields: fields,
        offset: reset ? 0 : _records.length,
        limit: limit,
        context: widget.recordContext,
      ),
      reset
          ? widget.rpc.callKw(widget.model, 'search_count', args: [domain], context: widget.recordContext)
          : Future<dynamic>.value(_total),
    ).wait;
    if (!mounted) return;
    setState(() {
      _records = reset ? records : [..._records, ...records];
      _total = total is int ? total : null;
      _hasMore = records.length == limit;
      _error = null;
    });
  }

  Future<void> _refresh() async {
    try {
      await _fetch(reset: true);
    } catch (e) {
      _onError(e);
    }
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || !_scroll.hasClients) return;
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 400) return;
    _loadingMore = true;
    _fetch().catchError(_onError).whenComplete(() => _loadingMore = false);
  }

  void _research() {
    setState(() => _records = []);
    _refresh();
  }

  Future<void> _openRecord(int? id) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecordFormScreen(
        rpc: widget.rpc,
        model: widget.model,
        recordId: id,
        formViewId: widget.viewIds['form'],
        recordContext: widget.recordContext,
        title: id == null ? 'New' : widget.title,
      ),
    ));
    _refresh();
  }

  void _toggleFilter(String name) {
    setState(() => _activeFilters.contains(name) ? _activeFilters.remove(name) : _activeFilters.add(name));
    _research();
  }

  Widget _filterChips() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final (f, _) in _filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(f.label),
                selected: _activeFilters.contains(f.name),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => _toggleFilter(f.name),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusPill(String text, dynamic key) {
    final (bg, fg) = statusColors(key, Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _card(Map<String, dynamic> record) {
    final fields = _views!.fields;
    final scheme = Theme.of(context).colorScheme;

    ArchField? badge;
    ArchField? amount;
    for (final f in _cardFields) {
      final type = fields[f.name]?['type'];
      if (badge == null &&
          ((type == 'selection' && (f.widget == 'badge' || f.name == 'state')) ||
              (type == 'many2one' && f.name == 'stage_id'))) {
        badge = f;
      }
      if (type == 'monetary') amount = f;
    }
    final details = [
      for (final f in _cardFields)
        if (f != badge && f != amount && f.name != 'name' && f.name != 'display_name')
          formatFieldValue(record[f.name], fields[f.name]!),
    ].where((s) => s.isNotEmpty).toList();
    final title = record['display_name']?.toString() ?? '';
    final badgeText = badge == null ? '' : formatFieldValue(record[badge.name], fields[badge.name]!);
    final amountText = amount == null ? '' : formatFieldValue(record[amount.name], fields[amount.name]!);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: record['id'] is int ? () => _openRecord(record['id'] as int) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LetterAvatar(text: title, size: 40, circle: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (amountText.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(amountText, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          ],
                        ],
                      ),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          details.first,
                          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (details.length > 1 || badgeText.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                details.skip(1).take(2).join(' · '),
                                style: TextStyle(fontSize: 12, color: scheme.outline),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (badgeText.isNotEmpty) _statusPill(badgeText, record[badge!.name]),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(ColorScheme scheme) {
    return ListView(
      children: [
        const SizedBox(height: 96),
        Icon(Icons.inbox_outlined, size: 56, color: scheme.outlineVariant),
        const SizedBox(height: 12),
        Text(
          _query.isNotEmpty || _activeFilters.isNotEmpty ? 'No records match' : 'No records yet',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          _query.isNotEmpty || _activeFilters.isNotEmpty ? 'Try another search or filter.' : 'Tap New to create one.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.outline),
        ),
      ],
    );
  }

  Widget _body() {
    if (_error != null) {
      return ErrorView.fromError(_error!, onRetry: () {
        setState(() => _error = null);
        _views == null ? _init() : _refresh();
      });
    }
    if (_views == null) return const Center(child: CircularProgressIndicator());

    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search ${widget.title.toLowerCase()}',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
            ),
            textInputAction: TextInputAction.search,
            onChanged: (q) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () {
                _query = q.trim();
                _research();
              });
            },
          ),
        ),
        if (_filters.isNotEmpty) _filterChips(),
        if (widget.domainIncomplete)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "Part of this menu's filter can't be applied in the app, so it may show more records than the web version.",
              style: TextStyle(fontSize: 12, color: scheme.onTertiaryContainer),
            ),
          ),
        if (_total != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
            child: Text(
              _total == 1 ? '1 record' : '${formatNumber(_total!, decimals: 0)} records',
              style: TextStyle(fontSize: 12, color: scheme.outline, fontWeight: FontWeight.w500),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: _records.isEmpty
                ? _emptyState(scheme)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.only(top: 2, bottom: 96),
                    itemCount: _records.length + (_hasMore ? 1 : 0),
                    itemBuilder: (_, i) => i < _records.length
                        ? _card(_records[i])
                        : const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final webPath = widget.webPath;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (webPath != null)
            IconButton(
              tooltip: 'Open in web',
              icon: const Icon(Icons.open_in_browser),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WebViewScreen(session: widget.rpc.session, path: webPath, title: widget.title),
              )),
            ),
        ],
      ),
      drawer: widget.drawer,
      floatingActionButton: _views != null && _canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _openRecord(null),
              icon: const Icon(Icons.add),
              label: const Text('New'),
            )
          : null,
      body: _body(),
    );
  }
}
