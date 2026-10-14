import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_info.dart';
import 'data/repository.dart';
import 'models/models.dart';
import 'services/api/api_settings.dart';
import 'services/cloud_service.dart';
import 'services/notification_service.dart';
import 'services/session.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'ui/app_update_dialog.dart';
import 'ui/auth/login_page.dart';
import 'ui/privacy_gate.dart';
import 'ui/shell.dart';

class ZudunApp extends StatelessWidget {
  const ZudunApp({
    super.key,
    required this.repository,
    required this.session,
    required this.cloud,
    required this.notifications,
  });

  final Repository repository;
  final Session session;
  final CloudService cloud;

  /// 系统通知服务（浏览器不支持时它自己会降级成「只发应用内提醒」）
  final NotificationService notifications;


  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Repository>.value(value: repository),
        ChangeNotifierProvider<Session>.value(value: session),
        ChangeNotifierProvider<CloudService>.value(value: cloud),
        Provider<ApiSettings>.value(value: cloud.settings),
        ChangeNotifierProvider<NotificationService>.value(
          value: notifications,
        ),
      ],
      child: _AppearanceWatcher(
        repository: repository,
        child: Consumer<Repository>(
        builder: (context, repository, _) {
          // 关键：令牌的明暗必须在建树**之前**定好。
          // 放在 MaterialApp 的 builder 里会因为「页面比它先重建」而读到旧值，
          // 表现就是切了深色还有些卡片 / 底栏没跟着变。
          Z.applyBrightness(_effectiveBrightness(repository));
          return MaterialApp(
          title: '租盾',
          debugShowCheckedModeBanner: false,
          theme: ZTheme.light(),
          darkTheme: ZTheme.dark(),
          // 外观偏好由「我的」页的开关与「设置 → 常规 → 外观」决定
          themeMode: _themeModeOf(repository.settings.appearance),
          locale: const Locale('zh', 'CN'),
          scrollBehavior: const ZScrollBehavior(),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            // 这里读到的 Theme 是 MaterialApp 之外的「环境主题」，
            // 并不是 themeMode 解析出来的那一套，拿它判断明暗会一直是浅色。
            // 令牌已经在上面按设置算好了，这里只管文字缩放。
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: media.textScaler.clamp(maxScaleFactor: 1.2),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const _StartupGate(),
          );
        },
      ),
      ),
    );
  }
}

/// 明暗真的变了的那一下，把整棵树推着重画一次。
///
/// 只换 MaterialApp 的主题是不够的：设计令牌（`Z.card` / `Z.ink` …）是全局静态
/// 值，而 `const` 出来的组件在父级重建时会被直接复用 —— Element 看到同一个实例
/// 就不重跑 build。于是切到深色后，首页「入住取证 / 水电燃气追踪 / 押金守护」那几张
/// 卡片、费用页整页底色都还停在浅色。这里给每个元素标一次脏，保证同一帧内所有读
/// 令牌的地方都换成新明暗；只是重画，滚动位置、表单内容、当前标签页都不受影响。
class _AppearanceWatcher extends StatefulWidget {
  const _AppearanceWatcher({required this.repository, required this.child});

  final Repository repository;
  final Widget child;

  @override
  State<_AppearanceWatcher> createState() => _AppearanceWatcherState();
}

class _AppearanceWatcherState extends State<_AppearanceWatcher>
    with WidgetsBindingObserver {
  /// 上一次已经推给令牌的明暗，用来判断「这次是不是真的变了」
  late Brightness _applied;

  @override
  void initState() {
    super.initState();
    // 注意：这里必须在 initState 里就取值。写成 `late xxx = ...` 的话，
    // 初始化会拖到第一次读取（也就是设置已经改完之后），基准值就是新值，
    // 结果「明明变了」却被判成没变。
    _applied = _effectiveBrightness(widget.repository);
    WidgetsBinding.instance.addObserver(this);
    widget.repository.addListener(_syncBrightness);
  }

  @override
  void dispose() {
    widget.repository.removeListener(_syncBrightness);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // 只在「跟随系统」时需要：固定浅色 / 深色时系统怎么变都不该影响界面
    if (widget.repository.settings.appearance != AppAppearance.system) return;
    widget.repository.notifyAppearanceChanged();
  }

  void _syncBrightness() {
    final next = _effectiveBrightness(widget.repository);
    if (next == _applied) return;
    _applied = next;
    Z.applyBrightness(next);
    // 万一是在 build 阶段里改的设置（正常路径不会），等这帧结束再标脏，
    // 免得在 build 里去标别的元素而触发断言
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => _markEverythingNeedsBuild(),
      );
      return;
    }
    _markEverythingNeedsBuild();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 当前「实际生效」的明暗：固定浅色 / 深色按设置，跟随系统则取平台当前值。
///
/// 刻意不用 `MediaQuery.platformBrightnessOf`：MaterialApp 上下两处必须读到同一个
/// 值，直接问 `platformDispatcher` 最稳，也不受 MediaQuery 更新时机影响。
Brightness _effectiveBrightness(Repository repository) =>
    switch (repository.settings.appearance) {
      AppAppearance.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
      AppAppearance.light => Brightness.light,
      AppAppearance.dark => Brightness.dark,
    };

/// 把整棵元素树标脏一次（为什么要这么做见 `_AppearanceWatcher` 的注释）。
/// `const` 组件不会因为父级重建而更新，只有被单独标脏才会重跑 build。
void _markEverythingNeedsBuild() {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return;

  void visit(Element element) {
    element.markNeedsBuild();
    element.visitChildren(visit);
  }

  visit(root);
}

ThemeMode _themeModeOf(AppAppearance appearance) => switch (appearance) {
  AppAppearance.system => ThemeMode.system,
  AppAppearance.light => ThemeMode.light,
  AppAppearance.dark => ThemeMode.dark,
};

/// 首屏分流：没登录、也没选择过本机模式时先看登录页（可走游客模式）
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  bool _updateChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 首次启动（或协议版本更新后）先征询同意：对齐应用市场合规要求
      await ensurePrivacyConsent(context);
      if (!mounted) return;
      await _checkUpdate();
    });
  }

  /// 启动时静默检查版本更新：请求失败、没有新版都安静放过
  Future<void> _checkUpdate() async {
    if (_updateChecked) return;
    _updateChecked = true;
    final cloud = context.read<CloudService>();
    try {
      final raw = await cloud.config.readSystemConfig(ApiSettings.appBrand);
      if (!mounted) return;
      await checkAppUpdateOnStart(
        context: context,
        rawConfig: raw,
        currentVersion: kAppVersion,
        onConsumed: () {},
      );
    } catch (_) {
      // 后台检查失败不打扰用户
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    // 进来就是登录页：两份协议由用户自己想看的时候点开（登录页底部有入口）
    return session.loggedIn || session.guestMode
        ? const AppShell()
        : const LoginPage();
  }
}
