import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  _ScreenState _state = _ScreenState.loading;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _state = _ScreenState.ready);
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

    final host = Uri.parse(widget.session.serverUrl).host;
    await WebViewCookieManager().setCookie(
      WebViewCookie(name: 'session_id', value: widget.session.sessionId, domain: host, path: '/'),
    );

    await _controller.loadRequest(Uri.parse('${widget.session.serverUrl}/web'));
  }

  Future<void> _signOut() async {
    await SessionStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tailorline'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _start),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              const DrawerHeader(child: Text('Tailorline', style: TextStyle(fontSize: 18))),
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
              title: "Can't reach ${Uri.parse(widget.session.serverUrl).host}",
              message: "The server didn't respond. It may be down.",
              onRetry: _start,
            ),
        ],
      ),
    );
  }
}
