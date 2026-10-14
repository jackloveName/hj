import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../services/notification_service.dart';
import '../services/session.dart';
import '../theme/tokens.dart';
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

class _AppShellState extends State<AppShell> {
  int _index = 0;
  String? _shownError;
  NotificationService? _notifications;
  Session? _session;
  bool _wasLoggedIn = false;

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
    setState(() => _index = 0);
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
        _TabBar(
          index: _index,
          onChanged: (value) => setState(() => _index = value),
        ),
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
