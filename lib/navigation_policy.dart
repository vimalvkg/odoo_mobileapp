enum NavigationTarget { inApp, external, signedOut }

const _inAppSchemes = {'about', 'data', 'blob', 'javascript'};

/// Decides where a main-frame navigation inside the WebView should go.
///
/// Pages on the configured Odoo server stay in the app; Odoo's login page
/// means the session ended; everything else (wa.me, tel:, mailto:, other
/// websites) is handed to the OS so the right app opens it.
NavigationTarget classifyNavigation(Uri target, Uri server) {
  if (_inAppSchemes.contains(target.scheme)) return NavigationTarget.inApp;

  final isWeb = target.scheme == 'http' || target.scheme == 'https';
  if (!isWeb || target.host != server.host) return NavigationTarget.external;

  if (isLoginPage(target)) return NavigationTarget.signedOut;
  return NavigationTarget.inApp;
}

/// Odoo redirects here when the session cookie is missing or expired, and
/// after the user logs out from the web client.
bool isLoginPage(Uri uri) {
  final path = uri.path.endsWith('/') ? uri.path.substring(0, uri.path.length - 1) : uri.path;
  return path == '/web/login';
}
