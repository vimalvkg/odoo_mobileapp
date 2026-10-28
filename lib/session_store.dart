import 'package:shared_preferences/shared_preferences.dart';

class Session {
  final String serverUrl;
  final String db;
  final String login;
  final String sessionId;

  Session({
    required this.serverUrl,
    required this.db,
    required this.login,
    required this.sessionId,
  });
}

class SessionStore {
  static const _keyServerUrl = 'server_url';
  static const _keyDb = 'db';
  static const _keyLogin = 'login';
  static const _keySessionId = 'session_id';

  static Future<Session?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString(_keyServerUrl);
    final db = prefs.getString(_keyDb);
    final login = prefs.getString(_keyLogin);
    final sessionId = prefs.getString(_keySessionId);
    if (serverUrl == null || db == null || login == null || sessionId == null) {
      return null;
    }
    return Session(serverUrl: serverUrl, db: db, login: login, sessionId: sessionId);
  }

  static Future<void> save(Session session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyServerUrl, session.serverUrl);
    await prefs.setString(_keyDb, session.db);
    await prefs.setString(_keyLogin, session.login);
    await prefs.setString(_keySessionId, session.sessionId);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyServerUrl);
    await prefs.remove(_keyDb);
    await prefs.remove(_keyLogin);
    await prefs.remove(_keySessionId);
  }
}
