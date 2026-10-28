import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_navigation.dart';
import '../navigation_policy.dart';
import '../session_store.dart';
import '../widgets/error_view.dart';

/// Odoo's own web client for whatever the native screens don't cover
/// (dashboards, Discuss, wizards, settings, reports).
class WebViewScreen extends StatefulWidget {
  final Session session;

  /// Server path to open, e.g. `/odoo/action-42` or `/odoo/sale.order/7`.
  final String path;
  final String title;
  final Widget? drawer;

  const WebViewScreen({super.key, required this.session, this.path = '/odoo', this.title = 'Web', this.drawer});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

enum _ScreenState { loading, ready, noConnection, serverUnreachable }

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  late final Uri _server = Uri.parse(widget.session.serverUrl);
  _ScreenState _state = _ScreenState.loading;
  int _progress = 100;

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

    await _controller.loadRequest(Uri.parse('${widget.session.serverUrl}${widget.path}'));
  }

  Future<NavigationDecision> _onNavigationRequest(NavigationRequest request) async {
    if (!request.isMainFrame) return NavigationDecision.navigate;
    final target = Uri.tryParse(request.url);
    if (target == null) return NavigationDecision.prevent;

    switch (classifyNavigation(target, _server)) {
      case NavigationTarget.inApp:
        return NavigationDecision.navigate;
      case NavigationTarget.signedOut:
        endSession(notice: sessionEndedNotice);
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
      endSession(notice: sessionEndedNotice);
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

  /// Android back walks the WebView history first, like a browser.
  Future<void> _onBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      await SystemNavigator.pop();
    }
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
          title: Text(widget.title),
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
        drawer: widget.drawer,
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
