import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../theme/tokens.dart';
import '../kit.dart';
import 'agreement_support.dart';

/// agreement H5 打开的三方页面；外部 App Store / 安装包链接交给系统打开。
class ThreeWebViewPage extends StatefulWidget {
  const ThreeWebViewPage({super.key, required this.url});

  final String url;

  @override
  State<ThreeWebViewPage> createState() => _ThreeWebViewPageState();
}

class _ThreeWebViewPageState extends State<ThreeWebViewPage> {
  WebViewController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (AgreementSupport.isExternalUrl(widget.url)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openExternal());
      return;
    }
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Z.page)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (!mounted || error.isForMainFrame == false) return;
            setState(() {
              _loading = false;
              _error = error.description;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
    _controller = controller;
  }

  Future<void> _openExternal() async {
    if (!mounted) return;
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(widget.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    if (!mounted) return;
    if (!launched) zToast(context, '无法打开外部链接');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Z.page,
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            if (_controller != null)
              WebViewWidget(controller: _controller!)
            else
              const SizedBox.expand(),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '页面加载失败：$_error',
                    textAlign: TextAlign.center,
                    style: ZText.body.copyWith(color: Z.ink3),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
