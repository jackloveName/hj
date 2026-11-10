import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/api/api_settings.dart';
import '../../services/cloud_service.dart';
import '../../theme/tokens.dart';
import '../kit.dart';
import 'agreement_support.dart';
import 'three_web_view_page.dart';

/// 登录后需要完成的服务 agreement 页面。
///
/// H5 通过 `uni.postMessage` 发送 three / account 操作。
/// 定位与通讯录能力不在此页面接入原生实现。
class AgreementPage extends StatefulWidget {
  const AgreementPage({super.key});

  @override
  State<AgreementPage> createState() => _AgreementPageState();
}

class _AgreementPageState extends State<AgreementPage> {
  static const _bridgeName = 'AgreementBridge';

  WebViewController? _controller;
  String _entryBaseUrl = '';
  String _webViewUrl = '';
  String _error = '服务配置读取失败，请稍后重试';
  bool _loading = true;
  bool _loadingRequest = false;
  double _statusHeight = 0;

  bool _actionPending = false;

  CloudService get _cloud => context.read<CloudService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEntryUrl());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _statusHeight = MediaQuery.paddingOf(context).top;
  }

  Future<void> _loadEntryUrl() async {
    if (_loadingRequest) return;
    _loadingRequest = true;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = '服务配置读取失败，请稍后重试';
      });
    }
    try {
      final config = await _cloud.agreement.readEntryConfig(
        ApiSettings.appBrand,
      );
      final entry = '${config['h5DownloadUrl'] ?? ''}'.trim();
      if (!AgreementSupport.isSafeWebUrl(entry)) {
        throw const FormatException('服务入口暂未配置');
      }
      _entryBaseUrl = entry;
      final next = _buildEntryUrl();
      if (!mounted) return;
      setState(() => _webViewUrl = next);
      await _loadUrl(next);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _entryBaseUrl = '';
        _webViewUrl = '';
        _controller = null;
        _loading = false;
        _error = error is FormatException ? error.message : '服务配置读取失败，请稍后重试';
      });
    } finally {
      _loadingRequest = false;
    }
  }

  String _buildEntryUrl() {
    return AgreementSupport.buildEntryUrl(
      baseUrl: _entryBaseUrl,
      token: _cloud.session.token,
      appName: ApiSettings.appBrand,
      statusHeight: _statusHeight,
    );
  }

  Future<void> _loadUrl(String url) async {
    if (!mounted || !AgreementSupport.isSafeWebUrl(url)) return;
    var controller = _controller;
    if (controller == null) {
      final nextController = WebViewController();
      await nextController.setJavaScriptMode(JavaScriptMode.unrestricted);
      await nextController.setBackgroundColor(Z.page);
      await nextController.addJavaScriptChannel(
        _bridgeName,
        onMessageReceived: (message) {
          final payload = AgreementSupport.messagePayload(message.message);
          if (payload != null) unawaited(_executeAction(payload));
        },
      );
      await nextController.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            // 尽早安装 H5 消息监听。
            unawaited(_installWebViewBridge(nextController));
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() => _loading = false);
            unawaited(_installWebViewBridge(nextController));
          },
          onNavigationRequest: (request) {
            if (!AgreementSupport.isExternalUrl(request.url)) {
              return NavigationDecision.navigate;
            }
            unawaited(_openExternal(request.url));
            return NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            if (!mounted || error.isForMainFrame == false) return;
            setState(() {
              _loading = false;
              _error = error.description;
            });
          },
        ),
      );
      _controller = nextController;
      controller = nextController;
    }
    setState(() {
      _webViewUrl = url;
      _loading = true;
      _error = '服务配置读取失败，请稍后重试';
    });
    await controller.loadRequest(Uri.parse(url));
  }

  Future<void> _installWebViewBridge(WebViewController controller) async {
    const script = r'''
      (function () {
        function send(payload) {
          try {
            window.AgreementBridge.postMessage(JSON.stringify(payload));
          } catch (_) {}
        }
        function forward(payload) {
          if (!payload) return;
          if (typeof payload === 'string') {
            try { payload = JSON.parse(payload); } catch (_) { return; }
          }
          if (payload.type === 'WEB_INVOKE_APPSERVICE') {
            var envelope = payload.data || {};
            if (envelope.name !== 'postMessage') return;
            payload = envelope.arg || {};
          }
          if (payload && typeof payload === 'object') send(payload);
        }
        window.__zudunAgreementSend = send;
        var uniObject = window.uni || {};
        uniObject.postMessage = function (payload) {
          forward(payload && payload.data ? payload.data : payload);
        };
        window.uni = uniObject;
        if (!window.__zudunAgreementListening) {
          window.__zudunAgreementListening = true;
          window.addEventListener('message', function (event) {
            forward(event && event.data);
          }, false);
        }
      })();
    ''';
    try {
      await controller.runJavaScript(script);
    } catch (_) {
      // 页面本身仍可用，消息桥在页面重载后会再次注入。
    }
  }

  Future<void> _executeAction(Map<String, dynamic> payload) async {
    final action = '${payload['action'] ?? ''}'.trim();
    if (action.isEmpty) return;

    if (action == 'three') {
      final target = '${payload['path'] ?? ''}'.trim();
      if (!AgreementSupport.isSafeWebUrl(target)) {
        if (mounted) zToast(context, '链接地址无效');
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => ThreeWebViewPage(url: target)),
      );
      return;
    }

    if (action != 'logout' && action != 'deleteAccount') return;
    if (_actionPending) return;
    _actionPending = true;
    try {
      if (action == 'logout') {
        await _cloud.logout();
      } else {
        await _cloud.destroyAccount();
      }
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) zToast(context, '操作失败：$error');
    } finally {
      _actionPending = false;
    }
  }

  Future<void> _openExternal(String url) async {
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    if (mounted && !launched) zToast(context, '无法打开外部链接');
  }

  @override
  Widget build(BuildContext context) {
    final hasWebView = _controller != null && _webViewUrl.isNotEmpty;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Z.page,
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              if (hasWebView)
                Positioned.fill(child: WebViewWidget(controller: _controller!)),
              if (_loading && hasWebView)
                const Center(child: CircularProgressIndicator()),
              if (!hasWebView)
                _AgreementState(
                  loading: _loading,
                  error: _error,
                  onRetry: _loadEntryUrl,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgreementState extends StatelessWidget {
  const _AgreementState({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Z.page,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Z.brandTint,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Z.line),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  size: 24,
                  color: Z.brand,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                loading ? '正在进入服务' : '暂时无法进入',
                style: ZText.title2.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                loading ? '正在校验账号与服务配置' : error,
                textAlign: TextAlign.center,
                style: ZText.body.copyWith(color: Z.ink3, height: 1.65),
              ),
              if (!loading) ...[
                const SizedBox(height: 22),
                SizedBox(
                  width: 150,
                  child: ZButton(label: '重新加载', onTap: onRetry),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
