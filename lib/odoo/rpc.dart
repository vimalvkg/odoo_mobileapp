import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../odoo_client.dart' show extractSessionId;
import '../session_store.dart';
import 'menus.dart';

class OdooException implements Exception {
  final String message;

  /// Python exception name from Odoo, e.g. `odoo.exceptions.AccessError`.
  final String? name;
  final bool isNetwork;

  const OdooException(this.message, {this.name, this.isNetwork = false});

  bool get isSessionExpired => name != null && name!.contains('SessionExpired');

  @override
  String toString() => message;
}

/// Field definitions and archs returned by `get_views`.
class ModelViews {
  final Map<String, Map<String, dynamic>> fields;

  /// Arch XML keyed by view type (`list`, `kanban`, `form`, `search`).
  final Map<String, String> archs;

  /// Field definitions of every model the views involve, e.g. the order
  /// line model of a sale order's inline line list.
  final Map<String, Map<String, Map<String, dynamic>>> models;

  const ModelViews(this.fields, this.archs, [this.models = const {}]);
}

Map<String, Map<String, dynamic>> _fieldDefs(dynamic modelInfo) {
  // Odoo 17+ nests the definitions under "fields"; 16 returns them directly.
  final raw = modelInfo is Map && modelInfo['fields'] is Map ? modelInfo['fields'] as Map : modelInfo as Map? ?? {};
  return {
    for (final e in raw.entries)
      if (e.value is Map) e.key.toString(): Map<String, dynamic>.from(e.value as Map),
  };
}

/// JSON-RPC client bound to a signed-in session. Everything goes through the
/// same endpoints as Odoo's own web client, so server-side access rights and
/// record rules apply unchanged.
class OdooRpc {
  final Session session;
  final http.Client _http;

  int? uid;
  String? userName;
  int? companyId;
  String? companyName;
  Map<String, dynamic> userContext = {};

  OdooRpc(this.session, {http.Client? client}) : _http = client ?? http.Client();

  /// Variables available to action domains and contexts.
  Map<String, dynamic> get evalEnv => {
        'uid': uid,
        'context': userContext,
        'allowed_company_ids': userContext['allowed_company_ids'] ?? <int>[],
        'current_company_id': (userContext['allowed_company_ids'] as List?)?.firstOrNull,
      };

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Cookie': 'session_id=${session.sessionId}',
      };

  Future<http.Response> _send(Future<http.Response> request) async {
    final http.Response response;
    try {
      response = await request.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const OdooException("The server didn't respond. It may be down.", isNetwork: true);
    } on SocketException {
      throw const OdooException("Can't reach the server. Check your connection.", isNetwork: true);
    } on http.ClientException {
      throw const OdooException("Can't reach the server. Check your connection.", isNetwork: true);
    }
    final rotated = extractSessionId(response.headers['set-cookie']);
    if (rotated != null && rotated != session.sessionId) {
      session.sessionId = rotated;
      unawaited(SessionStore.save(session));
    }
    if (response.statusCode != 200) {
      throw OdooException('Server returned ${response.statusCode}.');
    }
    return response;
  }

  dynamic _decode(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const OdooException('Unexpected response from the server.');
    }
  }

  Future<dynamic> post(String path, Map<String, dynamic> params) async {
    final response = await _send(_http.post(
      Uri.parse('${session.serverUrl}$path'),
      headers: _headers,
      body: jsonEncode({'jsonrpc': '2.0', 'method': 'call', 'params': params}),
    ));
    final decoded = _decode(response);
    if (decoded is! Map) throw const OdooException('Unexpected response from the server.');
    final error = decoded['error'];
    if (error is Map) {
      final data = error['data'];
      final name = data is Map ? data['name']?.toString() : null;
      final message = data is Map ? data['message']?.toString() : null;
      throw OdooException(message ?? error['message']?.toString() ?? 'Server error.', name: name);
    }
    return decoded['result'];
  }

  Future<dynamic> callKw(
    String model,
    String method, {
    List<dynamic> args = const [],
    Map<String, dynamic> kwargs = const {},
    Map<String, dynamic>? context,
  }) {
    return post('/web/dataset/call_kw/$model/$method', {
      'model': model,
      'method': method,
      'args': args,
      'kwargs': {
        ...kwargs,
        'context': {...userContext, ...?context},
      },
    });
  }

  /// Loads uid, name, company and the user context (lang, tz, companies).
  Future<void> loadSessionInfo() async {
    final info = await post('/web/session/get_session_info', {});
    if (info is! Map) return;
    uid = info['uid'] is int ? info['uid'] as int : null;
    userName = info['name']?.toString();
    final ctx = info['user_context'];
    userContext = ctx is Map ? Map<String, dynamic>.from(ctx) : {};
    final companies = info['user_companies'];
    if (companies is Map && companies['current_company'] is int) {
      final current = companies['current_company'] as int;
      companyId = current;
      userContext['allowed_company_ids'] = [current];
      final allowed = companies['allowed_companies'];
      final company = allowed is Map ? allowed['$current'] : null;
      if (company is Map) companyName = company['name']?.toString();
    }
  }

  /// Odoo's public logo route for the signed-in company.
  String? get companyLogoUrl =>
      companyId == null ? null : '${session.serverUrl}/web/binary/company_logo?company=$companyId';

  /// A record's image field, served by Odoo with access rights applied.
  String imageUrl(String model, int id, String field) => '${session.serverUrl}/web/image/$model/$id/$field';

  /// Headers that authenticate image requests ([imageUrl]) with the session.
  Map<String, String> get imageHeaders => {'Cookie': 'session_id=${session.sessionId}'};

  /// The company's brand colour (`primary_color`, set in Odoo's document
  /// layout settings), or null when unset or unavailable.
  Future<String?> loadCompanyColor() async {
    final id = companyId;
    if (id == null) return null;
    try {
      final rows = await read('res.company', [id], ['primary_color']);
      final color = rows.isEmpty ? null : rows.first['primary_color'];
      return color is String && color.isNotEmpty ? color : null;
    } on OdooException catch (e) {
      if (e.isSessionExpired) rethrow;
      return null;
    }
  }

  /// The installed apps (top-level menus) visible to this user.
  Future<List<OdooMenu>> loadApps() async {
    dynamic raw;
    try {
      raw = await callKw('ir.ui.menu', 'load_web_menus', args: [false]);
    } on OdooException catch (e) {
      if (e.isSessionExpired || e.isNetwork) rethrow;
      // Older/newer servers may only expose the web client's HTTP route.
      final response = await _send(_http.get(
        Uri.parse('${session.serverUrl}/web/webclient/load_menus'),
        headers: _headers,
      ));
      raw = _decode(response);
    }
    return parseMenus(raw);
  }

  Future<Map<String, dynamic>> loadAction(Object actionId, {Map<String, dynamic>? context}) async {
    final result = await post('/web/action/load', {
      'action_id': actionId,
      'context': {...userContext, ...?context},
    });
    if (result is! Map) throw const OdooException('This menu has nothing to open.');
    return Map<String, dynamic>.from(result);
  }

  /// [views] are `[viewId or false, viewType]` pairs, as in an action.
  Future<ModelViews> getViews(String model, List<List<dynamic>> views, {Map<String, dynamic>? context}) async {
    final result = await callKw(
      model,
      'get_views',
      args: [views],
      kwargs: {
        'options': {'toolbar': false, 'load_filters': false},
      },
      context: context,
    );
    if (result is! Map) throw const OdooException('Unexpected response from the server.');
    final models = {
      for (final e in ((result['models'] as Map?) ?? {}).entries) e.key.toString(): _fieldDefs(e.value),
    };
    final fields = models[model] ?? {};
    final archs = <String, String>{
      for (final e in ((result['views'] as Map?) ?? {}).entries)
        if (e.value is Map && (e.value as Map)['arch'] is String) e.key.toString(): (e.value as Map)['arch'] as String,
    };
    return ModelViews(fields, archs, models);
  }

  /// Runs a form header button of type `object`. Returns the action the
  /// method asked the client to open, if any.
  Future<dynamic> callButton(String model, String method, List<int> ids, {Map<String, dynamic>? context}) {
    return post('/web/dataset/call_button/$model/$method', {
      'model': model,
      'method': method,
      'args': [ids],
      'kwargs': {
        'context': {...userContext, ...?context},
      },
    });
  }

  Future<List<Map<String, dynamic>>> searchRead(
    String model, {
    List<dynamic> domain = const [],
    required List<String> fields,
    int offset = 0,
    int? limit,
    String? order,
    Map<String, dynamic>? context,
  }) async {
    final result = await callKw(model, 'search_read',
        kwargs: {
          'domain': domain,
          'fields': fields,
          'offset': offset,
          'limit': ?limit,
          'order': ?order,
        },
        context: context);
    return [for (final r in result as List) Map<String, dynamic>.from(r as Map)];
  }

  Future<List<Map<String, dynamic>>> read(String model, List<int> ids, List<String> fields,
      {Map<String, dynamic>? context}) async {
    final result = await callKw(model, 'read', args: [ids], kwargs: {'fields': fields}, context: context);
    return [for (final r in result as List) Map<String, dynamic>.from(r as Map)];
  }
}
