import 'package:shared_preferences/shared_preferences.dart';

class Session {
  final String serverUrl;
  final String db;
  final String login;
  /// Odoo can rotate the session id; [OdooRpc] updates it in place.
  String sessionId;

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

  /// Server, database and username from the last sign-in, kept after sign
  /// out so the login form can be prefilled. Never includes the password.
  static Future<({String serverUrl, String db, String login})?> lastLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString(_keyServerUrl);
    final db = prefs.getString(_keyDb);
    final login = prefs.getString(_keyLogin);
    if (serverUrl == null || db == null || login == null) return null;
    return (serverUrl: serverUrl, db: db, login: login);
  }

  /// Forgets the session but keeps [lastLogin] details.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySessionId);
  }
}

/// Device-side preferences. Per-database values are keyed by server and
/// database, so switching databases never mixes their branding or history.
class AppPrefs {
  static String _scope(String serverUrl, String db) => '$serverUrl|$db';

  static Future<int?> brandColor(String serverUrl, String db) async =>
      (await SharedPreferences.getInstance()).getInt('brand_color:${_scope(serverUrl, db)}');

  static Future<void> setBrandColor(String serverUrl, String db, int? argb) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'brand_color:${_scope(serverUrl, db)}';
    argb == null ? await prefs.remove(key) : await prefs.setInt(key, argb);
  }

  /// Most recent first.
  static Future<List<int>> recentMenus(String serverUrl, String db) async {
    final raw = (await SharedPreferences.getInstance()).getStringList('recent_menus:${_scope(serverUrl, db)}');
    return [for (final s in raw ?? const <String>[]) ?int.tryParse(s)];
  }

  static Future<void> addRecentMenu(String serverUrl, String db, int menuId) async {
    final recent = await recentMenus(serverUrl, db);
    recent
      ..remove(menuId)
      ..insert(0, menuId);
    await (await SharedPreferences.getInstance()).setStringList(
      'recent_menus:${_scope(serverUrl, db)}',
      [for (final id in recent.take(8)) '$id'],
    );
  }

  static Future<bool> biometricEnabled() async =>
      (await SharedPreferences.getInstance()).getBool('biometric') ?? false;

  static Future<void> setBiometricEnabled(bool on) async =>
      (await SharedPreferences.getInstance()).setBool('biometric', on);

  static Future<String?> themeMode() async => (await SharedPreferences.getInstance()).getString('theme_mode');

  static Future<void> setThemeMode(String mode) async =>
      (await SharedPreferences.getInstance()).setString('theme_mode', mode);
}

/// Menus pinned to the home screen, per server and database.
class PinnedMenus {
  static String _key(String serverUrl, String db) => 'pinned_menus:$serverUrl|$db';

  static Future<List<int>> load(String serverUrl, String db) async {
    final raw = (await SharedPreferences.getInstance()).getStringList(_key(serverUrl, db));
    return [for (final s in raw ?? const <String>[]) ?int.tryParse(s)];
  }

  /// Pins or unpins [menuId]; returns whether it is now pinned.
  static Future<bool> toggle(String serverUrl, String db, int menuId) async {
    final pins = await load(serverUrl, db);
    final pinned = !pins.remove(menuId);
    if (pinned) pins.add(menuId);
    await (await SharedPreferences.getInstance()).setStringList(_key(serverUrl, db), [for (final id in pins) '$id']);
    return pinned;
  }
}
