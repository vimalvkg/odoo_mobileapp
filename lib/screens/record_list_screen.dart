import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_navigation.dart';
import '../l10n.dart';
import '../odoo/domain.dart';
import '../odoo/expr.dart';
import '../odoo/format.dart';
import '../odoo/rpc.dart';
import '../odoo/view_arch.dart';
import '../theme.dart';
import '../widgets/error_view.dart';
import '../contact_actions.dart';
import '../widgets/record_avatar.dart';
import '../widgets/skeleton.dart';
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

  /// Shown above the title, e.g. the app ("Sales" above "Quotations").
  final String? subtitle;
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
    this.subtitle,
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

  /// Discovered from the model's fields, so every model gets what it supports.
  String? _imageField;
  String? _phoneField;
  String? _emailField;
  bool _canArchive = false;

  List<Map<String, dynamic>> _records = [];
  bool _hasMore = true;
  bool _loadingMore = false;
  Object? _error;
  String _query = '';
  int? _total;

  /// Sum of the list's `sum` column over all matching records, as Odoo's
  /// list footer shows it.
  num? _sum;

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
      final views = await widget.rpc.getViews(widget.model, [
        [widget.viewIds[cardType] ?? false, cardType],
        [widget.viewIds['search'] ?? false, 'search'],
      ], context: widget.recordContext);
      final cardArch = views.archs[cardType];
      if (cardArch == null) throw OdooException(tr('This model has no list view.'));

      final env = {
        ...widget.rpc.evalEnv,
        'context': {...widget.rpc.userContext, ...widget.recordContext},
      };
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
      _imageField = imageFieldOf(views.fields);
      _phoneField = [
        for (final n in phoneFieldNames)
          if (views.fields[n]?['type'] == 'char') n,
      ].firstOrNull;
      _emailField = [
        for (final n in emailFieldNames)
          if (views.fields[n]?['type'] == 'char') n,
      ].firstOrNull;
      _canArchive = views.fields['active']?['type'] == 'boolean';
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
    final fields = {'display_name', for (final f in _cardFields) f.name, ?_phoneField, ?_emailField}.toList();
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
    ).both;
    if (reset) _loadSum(domain);
    if (!mounted) return;
    setState(() {
      _records = reset ? records : [..._records, ...records];
      _total = total is int ? total : null;
      _hasMore = records.length == limit;
      _error = null;
    });
  }

  /// The column the list view totals (`sum="..."`), if any.
  ArchField? get _sumField => _cardFields
      .where(
        (f) =>
            f.attrs.containsKey('sum') &&
            const {'monetary', 'float', 'integer'}.contains(_views?.fields[f.name]?['type']),
      )
      .firstOrNull;

  Future<void> _loadSum(List<dynamic> domain) async {
    final field = _sumField;
    if (field == null) return;
    num? value;
    try {
      // Odoo 19 API, then the older read_group.
      final rows = await widget.rpc.callKw(
        widget.model,
        'formatted_read_group',
        args: [
          domain,
          <String>[],
          ['${field.name}:sum'],
        ],
        context: widget.recordContext,
      );
      if (rows is List && rows.isNotEmpty && rows.first is Map) {
        final row = rows.first as Map;
        value = (row['${field.name}:sum'] ?? row[field.name]) as num?;
      }
    } on OdooException catch (e) {
      if (e.isSessionExpired || e.isNetwork) return;
      try {
        final rows = await widget.rpc.callKw(
          widget.model,
          'read_group',
          args: [
            domain,
            ['${field.name}:sum'],
            <String>[],
          ],
          kwargs: {'lazy': false},
          context: widget.recordContext,
        );
        if (rows is List && rows.isNotEmpty && rows.first is Map) value = (rows.first as Map)[field.name] as num?;
      } catch (_) {
        value = null;
      }
    } catch (_) {
      value = null;
    }
    if (mounted) setState(() => _sum = value);
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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecordFormScreen(
          rpc: widget.rpc,
          model: widget.model,
          recordId: id,
          formViewId: widget.viewIds['form'],
          recordContext: widget.recordContext,
          title: id == null ? tr('New') : widget.title,
        ),
      ),
    );
    _refresh();
  }

  void _toggleFilter(String name) {
    HapticFeedback.selectionClick();
    setState(() => _activeFilters.contains(name) ? _activeFilters.remove(name) : _activeFilters.add(name));
    _research();
  }

  Widget _filterChips() {
    final scheme = Theme.of(context).colorScheme;
    final c = AppColors.of(context);
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final (f, _) in _filters)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Material(
                color: _activeFilters.contains(f.name) ? scheme.primary : c.card,
                shape: StadiumBorder(
                  side: BorderSide(color: _activeFilters.contains(f.name) ? scheme.primary : c.border),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => _toggleFilter(f.name),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Center(
                      child: Text(
                        f.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: _activeFilters.contains(f.name) ? FontWeight.w600 : FontWeight.w500,
                          color: _activeFilters.contains(f.name) ? scheme.onPrimary : c.ink,
                        ),
                      ),
                    ),
                  ),
                ),
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
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  /// The list's first date column, used for "Today / Yesterday" sections.
  ArchField? get _dateField =>
      _cardFields.where((f) => const {'date', 'datetime'}.contains(_views?.fields[f.name]?['type'])).firstOrNull;

  DateTime? _dateOf(Map<String, dynamic> record) {
    final f = _dateField;
    if (f == null) return null;
    final v = record[f.name];
    return _views!.fields[f.name]!['type'] == 'date' ? parseOdooDate(v) : parseOdooDateTime(v);
  }

  static String _bucket(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return tr('Today');
    if (diff == 1) return tr('Yesterday');
    if (diff == -1) return tr('Tomorrow');
    if (diff > 1 && diff < 7) return tr('This week');
    if (diff < 0 && diff > -7) return tr('Next 7 days');
    if (d.year == now.year && d.month == now.month) return tr('This month');
    return '${monthName(d.month)} ${d.year}';
  }

  /// Section headings by date, only when the records are actually ordered
  /// by that date (otherwise headings would repeat).
  List<String?> get _sections {
    final dates = [for (final r in _records) _dateOf(r)];
    if (dates.whereType<DateTime>().length < 2) return List.filled(_records.length, null);
    final known = dates.whereType<DateTime>().toList();
    var desc = true, asc = true;
    for (var i = 1; i < known.length; i++) {
      if (known[i].isAfter(known[i - 1])) desc = false;
      if (known[i].isBefore(known[i - 1])) asc = false;
    }
    if (!desc && !asc) return List.filled(_records.length, null);
    String? last;
    return [
      for (final d in dates)
        () {
          final b = d == null ? tr('No date') : _bucket(d);
          if (b == last) return null;
          last = b;
          return b;
        }(),
    ];
  }

  Widget _card(Map<String, dynamic> record) {
    final fields = _views!.fields;
    final c = AppColors.of(context);

    ArchField? badge;
    ArchField? amount;
    ArchField? party;
    for (final f in _cardFields) {
      final type = fields[f.name]?['type'];
      if (badge == null &&
          ((type == 'selection' && (f.widget == 'badge' || f.name == 'state')) ||
              (type == 'many2one' && f.name == 'stage_id'))) {
        badge = f;
      }
      if (type == 'monetary') amount = f;
      if (party == null && type == 'many2one' && const {'partner_id', 'customer_id', 'employee_id'}.contains(f.name)) {
        party = f;
      }
    }
    final date = _dateField;
    final name = record['display_name']?.toString() ?? '';
    final partyName = party == null ? '' : formatFieldValue(record[party.name], fields[party.name]!);
    // Orders and invoices read best as "Customer" with the reference below.
    final title = partyName.isNotEmpty && partyName != name ? partyName : name;
    final details = [
      if (title != name) name,
      for (final f in _cardFields)
        if (f != badge && f != amount && f != party && f != date && f.name != 'name' && f.name != 'display_name')
          formatFieldValue(record[f.name], fields[f.name]!),
    ].where((s) => s.isNotEmpty).take(3).join(' · ');
    final badgeText = badge == null ? '' : formatFieldValue(record[badge.name], fields[badge.name]!);
    final amountText = amount == null ? '' : formatFieldValue(record[amount.name], fields[amount.name]!);
    final dateText = date == null ? '' : formatFieldValue(record[date.name], fields[date.name]!);

    final card = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: record['id'] is int ? () => _openRecord(record['id'] as int) : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RecordAvatar(
                  rpc: widget.rpc,
                  model: widget.model,
                  id: record['id'] as int?,
                  imageField: _imageField,
                  text: title,
                  size: 44,
                  circle: false,
                ),
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
                            Text(amountText, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                          ],
                        ],
                      ),
                      if (details.isNotEmpty || badgeText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                details,
                                style: TextStyle(fontSize: 13, color: c.muted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (badgeText.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              _statusPill(badgeText, record[badge!.name]),
                            ],
                          ],
                        ),
                      ],
                      if (dateText.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.calendar_today_outlined, size: 13, color: c.muted),
                            const SizedBox(width: 5),
                            Text(dateText, style: TextStyle(fontSize: 12, color: c.muted)),
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
    final phone = _phoneField == null ? null : record[_phoneField];
    final email = _emailField == null ? null : record[_emailField];
    final hasContact = phone is String || email is String;
    final id = record['id'];
    if (id is! int || (!hasContact && !_canArchive)) return card;
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('record-$id'),
      direction: hasContact && _canArchive
          ? DismissDirection.horizontal
          : (hasContact ? DismissDirection.startToEnd : DismissDirection.endToStart),
      // With a single direction Flutter only shows [background].
      background: hasContact
          ? _swipeBackground(Icons.call_outlined, tr('Contact'), scheme.primary, AlignmentDirectional.centerStart)
          : _swipeBackground(Icons.archive_outlined, tr('Archive'), scheme.error, AlignmentDirectional.centerEnd),
      secondaryBackground: hasContact && _canArchive
          ? _swipeBackground(Icons.archive_outlined, tr('Archive'), scheme.error, AlignmentDirectional.centerEnd)
          : null,
      confirmDismiss: (direction) async {
        HapticFeedback.mediumImpact();
        if (direction == DismissDirection.startToEnd) {
          showContactSheet(
            context,
            title: title,
            phone: phone is String ? phone : null,
            email: email is String ? email : null,
          );
          return false;
        }
        return _archive(record);
      },
      child: card,
    );
  }

  Widget _swipeBackground(IconData icon, String label, Color color, AlignmentGeometry alignment) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: alignment,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  /// Archives through the model's own `action_archive`, with undo.
  Future<bool> _archive(Map<String, dynamic> record) async {
    final id = record['id'] as int;
    try {
      await widget.rpc.callKw(
        widget.model,
        'action_archive',
        args: [
          [id],
        ],
        context: widget.recordContext,
      );
    } catch (e) {
      if (mounted) handleRpcError(context, e);
      return false;
    }
    if (!mounted) return true;
    setState(() {
      _records = [
        for (final r in _records)
          if (r['id'] != id) r,
      ];
      if (_total != null) _total = _total! - 1;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('Archived {name}', {'name': record['display_name'] ?? ''})),
        action: SnackBarAction(
          label: tr('Undo'),
          onPressed: () async {
            try {
              await widget.rpc.callKw(
                widget.model,
                'action_unarchive',
                args: [
                  [id],
                ],
                context: widget.recordContext,
              );
              _refresh();
            } catch (e) {
              if (mounted) handleRpcError(context, e);
            }
          },
        ),
      ),
    );
    return true;
  }

  Widget _emptyState() {
    final c = AppColors.of(context);
    final filtered = _query.isNotEmpty || _activeFilters.isNotEmpty;
    return ListView(
      children: [
        const SizedBox(height: 96),
        Icon(Icons.inbox_outlined, size: 56, color: c.border),
        const SizedBox(height: 12),
        Text(
          filtered ? tr('No records match') : tr('No records yet'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          filtered ? tr('Try another search or filter.') : (_canCreate ? tr('Tap New to create one.') : ''),
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted),
        ),
      ],
    );
  }

  Widget _header() {
    final c = AppColors.of(context);
    final webPath = widget.webPath;
    final hasDrawer = widget.drawer != null;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.only(bottom: 12),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(4, 6, 8, 6),
              child: Row(
                children: [
                  Builder(
                    builder: (ctx) => IconButton(
                      tooltip: hasDrawer ? tr('Menu') : tr('Back'),
                      icon: Icon(hasDrawer ? Icons.menu : Icons.arrow_back),
                      onPressed: () => hasDrawer ? Scaffold.of(ctx).openDrawer() : Navigator.of(ctx).maybePop(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.subtitle != null && widget.subtitle != widget.title)
                          Text(widget.subtitle!, style: TextStyle(fontSize: 12, color: c.muted)),
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  if (webPath != null)
                    IconButton(
                      tooltip: tr('Open in web'),
                      icon: const Icon(Icons.open_in_browser),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              WebViewScreen(session: widget.rpc.session, path: webPath, title: widget.title),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: tr('Search {name}', {'name': isArabic ? widget.title : widget.title.toLowerCase()}),
                  isDense: true,
                  fillColor: c.ground,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
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
            if (_filters.isNotEmpty) ...[const SizedBox(height: 12), _filterChips()],
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return ErrorView.fromError(
        _error!,
        onRetry: () {
          setState(() => _error = null);
          _views == null ? _init() : _refresh();
        },
      );
    }
    if (_views == null) return const SkeletonCards();

    final c = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final sections = _sections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.domainIncomplete)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Text(
              tr("Part of this menu's filter can't be applied in the app, so it may show more records than the web version."),
              style: TextStyle(fontSize: 12, color: scheme.onTertiaryContainer),
            ),
          ),
        if (_total != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 13, color: c.muted),
                children: [
                  TextSpan(text: _total == 1 ? tr('1 record') : tr('{n} records', {'n': formatNumber(_total!, decimals: 0)})),
                  if (_sum != null && _total! > 0) ...[
                    TextSpan(text: ' · ${tr('total')} '),
                    TextSpan(
                      text: formatNumber(_sum!),
                      style: TextStyle(color: c.ink, fontWeight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: _records.isEmpty
                ? _emptyState()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.only(top: 4, bottom: 96),
                    itemCount: _records.length + (_hasMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= _records.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final section = sections[i];
                      if (section == null) return _card(_records[i]);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                            child: Text(
                              section.toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: c.muted,
                              ),
                            ),
                          ),
                          _card(_records[i]),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: widget.drawer,
      floatingActionButton: _views != null && _canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _openRecord(null),
              icon: const Icon(Icons.add),
              label: Text(tr('New')),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Expanded(child: _body()),
        ],
      ),
    );
  }
}
