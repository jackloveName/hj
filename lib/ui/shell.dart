import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../data/repository.dart';
import '../services/api/api_settings.dart';
import '../services/app_update.dart';
import '../services/cloud_service.dart';
import '../services/notification_service.dart';
import '../services/session.dart';
import '../theme/tokens.dart';
import 'app_update_dialog.dart';
import 'expense/expense_page.dart';
import 'home/home_page.dart';
import 'kit.dart';
import 'profile/profile_page.dart';
import 'property/tenancy_page.dart';

class _Tab {
  const _Tab(this.icon, this.activeIcon, this.label);

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

const List<_Tab> _tabs = [
  _Tab(Icons.home_outlined, Icons.home_rounded, '首页'),
  _Tab(Icons.home_work_outlined, Icons.home_work_rounded, '租住'),
  _Tab(
    Icons.account_balance_wallet_outlined,
    Icons.account_balance_wallet_rounded,
    '费用',
  ),
  _Tab(Icons.person_outline_rounded, Icons.person_rounded, '我的'),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;
  String? _shownError;
  NotificationService? _notifications;
  Session? _session;
  bool _wasLoggedIn = false;

  /// 正在查，避免连点标签页 / 前后台来回切时并发请求
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    // 前后台切换要能重新查更新
    WidgetsBinding.instance.addObserver(this);
    // 进 App 后的第一屏就是首页，所以更新检查挂在这里：
    // 弹窗正好落在首页上，也不会盖在「同意协议」页或登录页上。
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdateOnHome());
  }

  /// 从后台切回来时：如果停在首页，重新查一次更新
  /// （用户切出去逛了一圈再回来，正是想知道有没有新版的时候）
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_index != 0) return;
    _checkUpdateOnHome();
  }

  /// 切标签页：回到「首页」就再查一次更新
  void _selectTab(int value) {
    setState(() => _index = value);
    if (value == 0) _checkUpdateOnHome();
  }

  /// 进首页时的静默更新检查：有更高版本就弹升级框。
  ///
  /// 刻意**不记**「这个版本弹过」：每次进首页（进 App、切回首页、从后台回来）
  /// 都重新问一次服务端，只要有更新就弹 —— 用户点掉之后，再进首页还会弹。
  /// 请求失败不打扰用户，下次进首页再试。
  Future<void> _checkUpdateOnHome() async {
    if (_checkingUpdate) return;
    _checkingUpdate = true;
    try {
      final raw = await context.read<CloudService>().config.readSystemConfig(
        ApiSettings.appBrand,
      );
      if (!mounted) return;
      final info = newerUpdate(raw, kAppVersion);
      if (info == null) return;
      await showAppUpdateDialog(
        context: context,
        info: info,
        currentVersion: kAppVersion,
      );
    } catch (_) {
      // 后台检查失败不打扰用户，下次回首页再试
    } finally {
      _checkingUpdate = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifications = context.read<NotificationService>();
    if (!identical(_notifications, notifications)) {
      _notifications?.removeListener(_onNotificationTap);
      _notifications = notifications..addListener(_onNotificationTap);
    }
    final session = context.read<Session>();
    if (!identical(_session, session)) {
      _session?.removeListener(_onSessionChanged);
      _session = session..addListener(_onSessionChanged);
      _wasLoggedIn = session.loggedIn;
    }
  }

  /// 登录成功后回到首页（用户登录进来第一眼应该是首页，而不是停在「我的」）
  void _onSessionChanged() {
    final loggedIn = _session?.loggedIn ?? false;
    if (loggedIn == _wasLoggedIn) return;
    _wasLoggedIn = loggedIn;
    if (!loggedIn || !mounted) return;
    _selectTab(0);
  }

  /// 点系统通知进来时，直接落到对应的标签页
  void _onNotificationTap() {
    final slot = _notifications?.pendingTapSlot;
    if (slot == null) return;
    _notifications?.clearPendingTap();
    if (!mounted) return;
    setState(() {
      _index = switch (slot) {
        PlanSlot.contractExpire || PlanSlot.depositReturn => 1, // 租住
        PlanSlot.rentDue || PlanSlot.utilityReading => 2, // 费用
      };
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifications?.removeListener(_onNotificationTap);
    _session?.removeListener(_onSessionChanged);
    super.dispose();
  }

  static const List<Widget> _pages = [
    HomePage(),
    TenancyPage(),
    ExpensePage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final isWide = MediaQuery.sizeOf(context).width > Z.contentMaxWidth + 48;

    // 任何写入失败（数据落盘 / 照片保存）都统一提示一次，避免静默失败
    final error = repository.lastError;
    if (error != null && error != _shownError) {
      _shownError = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // 写入失败这类必须让用户看到，用顶部提示（红色调），不再用底部条
        zToast(context, error, tone: ZTone.danger);
        repository.clearError();
      });
    } else if (error == null) {
      _shownError = null;
    }

    final body = Column(
      children: [
        Expanded(
          child: IndexedStack(index: _index, children: _pages),
        ),
        _TabBar(index: _index, onChanged: _selectTab),
      ],
    );

    if (!isWide) return Scaffold(body: body);

    return Scaffold(
      backgroundColor: Z.shell,
      body: Center(
        child: Container(
          width: Z.contentMaxWidth,
          margin: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: Z.page,
            borderRadius: BorderRadius.circular(24),
            boxShadow: Z.e3,
          ),
          clipBehavior: Clip.antiAlias,
          child: body,
        ),
      ),
    );
  }
}

/// 底部 Tab —— 对应设计稿 .tabbar
class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Z.card,
        border: Border(top: BorderSide(color: Z.line)),
      ),
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onChanged(i),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      i == index ? _tabs[i].activeIcon : _tabs[i].icon,
                      size: 21,
                      color: i == index ? Z.brand : Z.ink4,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _tabs[i].label,
                      style: TextStyle(
                        fontFamily: Z.font,
                        fontFamilyFallback: Z.fallback,
                        fontSize: 11,
                        fontWeight: i == index
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: i == index ? Z.brand : Z.ink4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
