import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'l10n.dart';

enum AuthOutcome { success, invalidCredentials, noConnection, serverUnreachable, unknown }

class AuthResult {
  final AuthOutcome outcome;
  final String? sessionId;
  final String? errorMessage;

  /// The user's Odoo language, e.g. `ar_001`.
  final String? lang;

  AuthResult.ok(this.sessionId, {this.lang})
      : outcome = AuthOutcome.success,
        errorMessage = null;

  AuthResult.failure(this.outcome, this.errorMessage)
      : sessionId = null,
        lang = null;
}

bool _isLocalHost(String hostAndPort) {
  final host = hostAndPort.split(':').first;
  return host == 'localhost' || host == '127.0.0.1' || host.startsWith('192.168.') || host.startsWith('10.');
}

String normalizeServerUrl(String input) {
  var url = input.trim();
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    final scheme = _isLocalHost(url) ? 'http' : 'https';
    url = '$scheme://$url';
  }
  if (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

class OdooClient {
  static Future<AuthResult> authenticate({
    required String serverUrl,
    required String db,
    required String login,
    required String password,
  }) async {
    final uri = Uri.parse('$serverUrl/web/session/authenticate');
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {'db': db, 'login': login, 'password': password},
    });

    try {
      final response = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return AuthResult.failure(AuthOutcome.serverUnreachable, tr('Server returned {code}.', {'code': response.statusCode}));
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final result = decoded['result'] as Map<String, dynamic>?;

      if (result == null || result['uid'] == null || result['uid'] == false) {
        return AuthResult.failure(AuthOutcome.invalidCredentials, tr('Wrong username or password.'));
      }

      final setCookie = response.headers['set-cookie'];
      final sessionId = extractSessionId(setCookie);
      if (sessionId == null) {
        return AuthResult.failure(AuthOutcome.unknown, tr('No session returned by the server.'));
      }

      final context = result['user_context'];
      return AuthResult.ok(sessionId, lang: context is Map ? context['lang']?.toString() : null);
    } on TimeoutException {
      return AuthResult.failure(AuthOutcome.serverUnreachable, tr("The server didn't respond. It may be down."));
    } on SocketException catch (e) {
      final msg = e.message.toLowerCase();
      final isNetworkDown = msg.contains('network is unreachable') || msg.contains('no address associated');
      return AuthResult.failure(
        isNetworkDown ? AuthOutcome.noConnection : AuthOutcome.serverUnreachable,
        isNetworkDown ? tr('Check your internet and try again.') : tr("Can't reach the server."),
      );
    } catch (e) {
      return AuthResult.failure(AuthOutcome.unknown, tr('Something went wrong. Try again.'));
    }
  }

  /// Odoo serves each database's company logo without authentication, so the
  /// login screen can show it as soon as server and database are known.
  static String publicLogoUrl(String serverUrl, String db) =>
      '$serverUrl/web/binary/company_logo?dbname=${Uri.encodeQueryComponent(db)}';

  /// Databases on the server, or null when it doesn't allow listing them.
  static Future<List<String>?> listDatabases(String serverUrl) async {
    try {
      final response = await http
          .post(
            Uri.parse('$serverUrl/web/database/list'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'jsonrpc': '2.0', 'method': 'call', 'params': {}}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final result = (jsonDecode(response.body) as Map<String, dynamic>)['result'];
      return result is List ? [for (final db in result) db.toString()] : null;
    } catch (_) {
      return null;
    }
  }

  /// Ends the session on the server so a stolen cookie stops working after
  /// sign out. Best effort: never throws, and callers needn't wait for it.
  static Future<void> destroySession({required String serverUrl, required String sessionId}) async {
    try {
      await http
          .post(
            Uri.parse('$serverUrl/web/session/destroy'),
            headers: {'Content-Type': 'application/json', 'Cookie': 'session_id=$sessionId'},
            body: jsonEncode({'jsonrpc': '2.0', 'method': 'call', 'params': {}}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Offline or server down: the local session is cleared regardless.
    }
  }
}

/// `package:http` folds multiple Set-Cookie headers into one comma-joined
/// string, so split on both separators before looking for `session_id`.
String? extractSessionId(String? setCookieHeader) {
  if (setCookieHeader == null) return null;
  for (final part in setCookieHeader.split(RegExp('[;,]'))) {
    final trimmed = part.trim();
    if (trimmed.startsWith('session_id=')) {
      final value = trimmed.substring('session_id='.length);
      return value.isEmpty ? null : value;
    }
  }
  return null;
}
