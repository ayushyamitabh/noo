import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../providers/server_provider.dart';

/// Every Login Flow v2 page - first login or an additional account -
/// rendered in Flutter's own WebView rather than a Chrome Custom Tab or
/// url_launcher's `LaunchMode.inAppWebView`. The latter hosts a bare native
/// WebView Activity with no chrome of its own: no close button, and on at
/// least some devices it draws edge-to-edge and hides the status bar with
/// no way back short of the OS back gesture. A normal Scaffold/AppBar here
/// gets the status bar/safe-area handling and a close button for free,
/// exactly like every other screen in the app - and unlike a Custom Tab,
/// this screen can close itself automatically once login succeeds.
///
/// See ServerProvider.startLoginFlow's doc comment for the full rationale.
class LoginWebViewView extends StatefulWidget {
  final Uri url;

  const LoginWebViewView({super.key, required this.url});

  @override
  State<LoginWebViewView> createState() => _LoginWebViewViewState();
}

class _LoginWebViewViewState extends State<LoginWebViewView> {
  late final WebViewController _controller;
  bool _pageLoading = true;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _pageLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _pageLoading = false);
          },
        ),
      )
      ..loadRequest(widget.url);
  }

  void _cancel() {
    context.read<ServerProvider>().cancelLoginFlow();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ServerProvider>();

    // The login flow finished (success or error) or was cancelled
    // elsewhere - close this screen automatically rather than leaving it
    // sitting open over a flow that's no longer awaiting the browser.
    if (!_popped &&
        provider.loginFlowStatus != LoginFlowStatus.awaitingBrowser) {
      _popped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sign in'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel',
            onPressed: _cancel,
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_pageLoading) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
