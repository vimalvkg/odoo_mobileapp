import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'odoo/rpc.dart';
import 'odoo_client.dart';
import 'screens/login_screen.dart';
import 'session_store.dart';

final navigatorKey = GlobalKey<NavigatorState>();

const sessionEndedNotice = 'Your session has ended. Sign in again to continue.';

bool _endingSession = false;

/// Forgets the session and returns to the login screen from anywhere.
/// Pass [destroy] to also end the session on the server (explicit sign out).
Future<void> endSession({String? notice, Session? destroy}) async {
  if (_endingSession) return;
  _endingSession = true;
  try {
    if (destroy != null) {
      unawaited(OdooClient.destroySession(serverUrl: destroy.serverUrl, sessionId: destroy.sessionId));
    }
    await SessionStore.clear();
    await WebViewCookieManager().clearCookies();
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(notice: notice)),
      (_) => false,
    );
  } finally {
    _endingSession = false;
  }
}

String errorMessage(Object error) =>
    error is OdooException ? error.message : 'Something went wrong. Try again.';

/// Shows an RPC failure as a snackbar, or signs out when it means the
/// session ended. Returns true if the session ended.
bool handleRpcError(BuildContext context, Object error) {
  if (error is OdooException && error.isSessionExpired) {
    endSession(notice: sessionEndedNotice);
    return true;
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(error))));
  return false;
}
