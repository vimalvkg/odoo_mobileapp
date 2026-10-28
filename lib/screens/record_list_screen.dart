import 'dart:async';

import 'package:flutter/material.dart';

import '../app_navigation.dart';
import '../odoo/domain.dart';
import '../odoo/expr.dart';
import '../odoo/format.dart';
import '../odoo/rpc.dart';
import '../odoo/view_arch.dart';
import '../widgets/error_view.dart';
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
    final records = await widget.rpc.searchRead(
      widget.model,
      domain: _domain,
      fields: fields,
      offset: reset ? 0 : _records.length,
      limit: limit,
      context: widget.recordContext,
    );
    if (!mounted) return;
    setState(() {
      _records = reset ? records : [..._records, ...records];
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

  void _showFilters() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var i = 0; i < _filters.length; i++) ...[
                  if (i > 0 && _filters[i].$1.group != _filters[i - 1].$1.group) const Divider(),
                  CheckboxListTile(
                    title: Text(_filters[i].$1.label),
                    value: _activeFilters.contains(_filters[i].$1.name),
                    onChanged: (on) {
                      final name = _filters[i].$1.name;
                      setSheetState(() => on == true ? _activeFilters.add(name) : _activeFilters.remove(name));
                      _research();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> record) {
    final fields = _views!.fields;
    final theme = Theme.of(context);

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
    final subtitle = [
      for (final f in _cardFields)
        if (f != badge && f != amount && f.name != 'name' && f.name != 'display_name')
          formatFieldValue(record[f.name], fields[f.name]!),
    ].where((s) => s.isNotEmpty).take(3).join(' · ');
    final badgeText = badge == null ? '' : formatFieldValue(record[badge.name], fields[badge.name]!);
    final amountText = amount == null ? '' : formatFieldValue(record[amount.name], fields[amount.name]!);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: record['id'] is int ? () => _openRecord(record['id'] as int) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record['display_name']?.toString() ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 13, color: theme.colorScheme.outline),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (amountText.isNotEmpty || badgeText.isNotEmpty) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (amountText.isNotEmpty) Text(amountText, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (badgeText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSecondaryContainer),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
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

    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search', isDense: true),
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
        if (widget.domainIncomplete)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "Part of this menu's filter can't be applied in the app, so it may show more records than the web version.",
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onTertiaryContainer),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: _records.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Center(child: Text('No records', style: TextStyle(color: theme.colorScheme.outline))),
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.only(top: 4, bottom: 88),
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
          if (_filters.isNotEmpty)
            IconButton(
              tooltip: 'Filters',
              onPressed: _showFilters,
              icon: Badge(
                isLabelVisible: _activeFilters.isNotEmpty,
                label: Text('${_activeFilters.length}'),
                child: const Icon(Icons.filter_list),
              ),
            ),
          if (webPath != null)
            IconButton(
              tooltip: 'Open in web',
              icon: const Icon(Icons.language),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WebViewScreen(session: widget.rpc.session, path: webPath, title: widget.title),
              )),
            ),
        ],
      ),
      drawer: widget.drawer,
      floatingActionButton: _views != null && _canCreate
          ? FloatingActionButton(tooltip: 'New', onPressed: () => _openRecord(null), child: const Icon(Icons.add))
          : null,
      body: _body(),
    );
  }
}
