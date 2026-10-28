import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../navigation_policy.dart';
import '../odoo_client.dart';
import '../session_store.dart';
import '../widgets/error_view.dart';
import 'login_screen.dart';

class WebViewScreen extends StatefulWidget {
  final Session session;

  const WebViewScreen({super.key, required this.session});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

enum _ScreenState { loading, ready, noConnection, serverUnreachable }

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  late final Uri _server = Uri.parse(widget.session.serverUrl);
  _ScreenState _state = _ScreenState.loading;
  int _progress = 100;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onUrlChange: (change) => _checkSignedOut(change.url),
          onPageStarted: _checkSignedOut,
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageFinished: (_) {
            if (mounted && _state == _ScreenState.loading) setState(() => _state = _ScreenState.ready);
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            if (error.isForMainFrame ?? true) {
              setState(() => _state = _ScreenState.serverUnreachable);
            }
          },
        ),
      );
    _start();
  }

  Future<void> _start() async {
    setState(() => _state = _ScreenState.loading);

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      if (mounted) setState(() => _state = _ScreenState.noConnection);
      return;
    }

    await WebViewCookieManager().setCookie(
      WebViewCookie(name: 'session_id', value: widget.session.sessionId, domain: _server.host, path: '/'),
    );

    await _controller.loadRequest(Uri.parse('${widget.session.serverUrl}/web'));
  }

  Future<NavigationDecision> _onNavigationRequest(NavigationRequest request) async {
    if (!request.isMainFrame) return NavigationDecision.navigate;
    final target = Uri.tryParse(request.url);
    if (target == null) return NavigationDecision.prevent;

    switch (classifyNavigation(target, _server)) {
      case NavigationTarget.inApp:
        return NavigationDecision.navigate;
      case NavigationTarget.signedOut:
        _endSession(notice: 'Your session has ended. Sign in again to continue.');
        return NavigationDecision.prevent;
      case NavigationTarget.external:
        _openExternally(target);
        return NavigationDecision.prevent;
    }
  }

  /// Server-side redirects don't always go through [_onNavigationRequest],
  /// so also watch the URL the page actually lands on.
  void _checkSignedOut(String? url) {
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host == _server.host && isLoginPage(uri)) {
      _endSession(notice: 'Your session has ended. Sign in again to continue.');
    }
  }

  Future<void> _openExternally(Uri uri) async {
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Thrown on some platforms when no app handles the scheme.
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No app installed to open ${uri.scheme == 'https' ? uri.host : uri.scheme} links.')),
      );
    }
  }

  /// Android back walks the WebView history first and only leaves the app
  /// from the first page, like a browser.
  Future<void> _onBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else {
      await SystemNavigator.pop();
    }
  }

  Future<void> _signOut() async {
    unawaited(OdooClient.destroySession(serverUrl: widget.session.serverUrl, sessionId: widget.session.sessionId));
    await _endSession();
  }

  Future<void> _endSession({String? notice}) async {
    if (_leaving) return;
    _leaving = true;
    await SessionStore.clear();
    await WebViewCookieManager().clearCookies();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => LoginScreen(notice: notice)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tailorline'),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'Reload', onPressed: _start),
          ],
          bottom: _state == _ScreenState.ready && _progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(value: _progress / 100, minHeight: 2),
                )
              : null,
        ),
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              children: [
                DrawerHeader(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text('Tailorline', style: TextStyle(fontSize: 18)),
                      const SizedBox(height: 4),
                      Text(widget.session.login, style: const TextStyle(fontSize: 13)),
                      Text(
                        '${_server.host} · ${widget.session.db}',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('Home'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _controller.loadRequest(Uri.parse('${widget.session.serverUrl}/web'));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('Reload'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _start();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign out'),
                  onTap: _signOut,
                ),
              ],
            ),
          ),
        ),
        body: Stack(
          children: [
            if (_state == _ScreenState.ready || _state == _ScreenState.loading)
              WebViewWidget(controller: _controller),
            if (_state == _ScreenState.loading)
              const Center(child: CircularProgressIndicator()),
            if (_state == _ScreenState.noConnection)
              ErrorView(
                icon: Icons.cloud_off,
                title: 'No connection',
                message: 'Check your internet and try again.',
                onRetry: _start,
              ),
            if (_state == _ScreenState.serverUnreachable)
              ErrorView(
                icon: Icons.dns_outlined,
                title: "Can't reach ${_server.host}",
                message: "The server didn't respond. It may be down.",
                onRetry: _start,
              ),
          ],
        ),
      ),
    );
  }
}
