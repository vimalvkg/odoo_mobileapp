import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

enum AuthOutcome { success, invalidCredentials, noConnection, serverUnreachable, unknown }

class AuthResult {
  final AuthOutcome outcome;
  final String? sessionId;
  final String? errorMessage;

  AuthResult.ok(this.sessionId)
      : outcome = AuthOutcome.success,
        errorMessage = null;

  AuthResult.failure(this.outcome, this.errorMessage) : sessionId = null;
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
        return AuthResult.failure(AuthOutcome.serverUnreachable, 'Server returned ${response.statusCode}.');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final result = decoded['result'] as Map<String, dynamic>?;

      if (result == null || result['uid'] == null || result['uid'] == false) {
        return AuthResult.failure(AuthOutcome.invalidCredentials, 'Wrong username or password.');
      }

      final setCookie = response.headers['set-cookie'];
      final sessionId = _extractSessionId(setCookie);
      if (sessionId == null) {
        return AuthResult.failure(AuthOutcome.unknown, 'No session returned by the server.');
      }

      return AuthResult.ok(sessionId);
    } on TimeoutException {
      return AuthResult.failure(AuthOutcome.serverUnreachable, "The server didn't respond. It may be down.");
    } on SocketException catch (e) {
      final msg = e.message.toLowerCase();
      final isNetworkDown = msg.contains('network is unreachable') || msg.contains('no address associated');
      return AuthResult.failure(
        isNetworkDown ? AuthOutcome.noConnection : AuthOutcome.serverUnreachable,
        isNetworkDown ? 'Check your internet and try again.' : "Can't reach the server.",
      );
    } catch (e) {
      return AuthResult.failure(AuthOutcome.unknown, 'Something went wrong. Try again.');
    }
  }

  static String? _extractSessionId(String? setCookieHeader) {
    if (setCookieHeader == null) return null;
    for (final part in setCookieHeader.split(';')) {
      final trimmed = part.trim();
      if (trimmed.startsWith('session_id=')) {
        return trimmed.substring('session_id='.length);
      }
    }
    return null;
  }
}
