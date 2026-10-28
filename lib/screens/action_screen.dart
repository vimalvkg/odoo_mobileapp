import 'package:flutter/material.dart';

import '../app_navigation.dart';
import '../odoo/domain.dart';
import '../odoo/menus.dart';
import '../odoo/rpc.dart';
import '../session_store.dart';
import '../widgets/app_menu_drawer.dart';
import '../widgets/error_view.dart';
import 'record_form_screen.dart';
import 'record_list_screen.dart';
import 'webview_screen.dart';

/// Models whose forms only make sense in the full web client.
const _webOnlyModels = {'res.config.settings'};

/// Loads an `ir.actions.*` record and shows it: window actions as native
/// list/form screens, everything else (dashboards, Discuss, reports,
/// wizards) in the web client.
class ActionScreen extends StatefulWidget {
  final OdooRpc rpc;
  final int actionId;
  final String title;
  final OdooMenu? app;
  final int? menuId;

  const ActionScreen({
    super.key,
    required this.rpc,
    required this.actionId,
    required this.title,
    this.app,
    this.menuId,
  });

  @override
  State<ActionScreen> createState() => _ActionScreenState();
}

class _ActionScreenState extends State<ActionScreen> {
  Map<String, dynamic>? _action;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final menuId = widget.menuId;
    if (menuId != null) {
      AppPrefs.addRecentMenu(widget.rpc.session.serverUrl, widget.rpc.session.db, menuId);
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final action = await widget.rpc.loadAction(widget.actionId);
      if (mounted) setState(() => _action = action);
    } catch (e) {
      if (!mounted) return;
      if (e is OdooException && e.isSessionExpired) {
        endSession(notice: sessionEndedNotice);
        return;
      }
      setState(() => _error = e);
    }
  }

  Widget? get _drawer {
    final app = widget.app;
    return app == null ? null : AppMenuDrawer(rpc: widget.rpc, app: app, currentMenuId: widget.menuId);
  }

  /// `[[viewId or false, type]]`, with Odoo <18 `tree` renamed to `list`.
  static List<List<dynamic>> _views(Map<String, dynamic> action) {
    final raw = action['views'];
    final List<List<dynamic>> views;
    if (raw is List && raw.isNotEmpty) {
      views = [for (final v in raw) if (v is List && v.length == 2) [v[0], v[1]]];
    } else {
      final modes = (action['view_mode'] as String? ?? 'list,form').split(',');
      views = [for (final m in modes) [false, m.trim()]];
    }
    for (final v in views) {
      if (v[1] == 'tree') v[1] = 'list';
    }
    return views;
  }

  Widget _webFallback(String title) => WebViewScreen(
        session: widget.rpc.session,
        path: '/odoo/action-${widget.actionId}',
        title: title,
        drawer: _drawer,
      );

  @override
  Widget build(BuildContext context) {
    final action = _action;
    if (action == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        drawer: _drawer,
        body: _error != null
            ? ErrorView.fromError(_error!, onRetry: () {
                setState(() => _error = null);
                _load();
              })
            : const Center(child: CircularProgressIndicator()),
      );
    }

    final title = (action['display_name'] ?? action['name'] ?? widget.title).toString();
    final model = action['res_model'];
    if (action['type'] != 'ir.actions.act_window' ||
        model is! String ||
        action['target'] == 'new' ||
        _webOnlyModels.contains(model)) {
      return _webFallback(title);
    }

    final env = widget.rpc.evalEnv;
    final views = _views(action);
    final viewIds = <String, int?>{for (final v in views) v[1] as String: v[0] is int ? v[0] as int : null};
    final actionContext = parseContext(action['context'], env) ?? {};
    final resId = action['res_id'];

    if ((views.isNotEmpty && views.first[1] == 'form') || (resId is int && resId > 0)) {
      return RecordFormScreen(
        rpc: widget.rpc,
        model: model,
        recordId: resId is int && resId > 0 ? resId : null,
        formViewId: viewIds['form'],
        recordContext: actionContext,
        title: title,
        drawer: _drawer,
      );
    }

    if (!viewIds.containsKey('list') && !viewIds.containsKey('kanban')) {
      // Calendar, pivot, graph, map... only views.
      return _webFallback(title);
    }

    final domain = parseDomain(action['domain'], env);
    return RecordListScreen(
      rpc: widget.rpc,
      model: model,
      title: title,
      domain: domain ?? const [],
      domainIncomplete: domain == null,
      recordContext: actionContext,
      viewIds: viewIds,
      webPath: '/odoo/action-${widget.actionId}',
      drawer: _drawer,
    );
  }
}
